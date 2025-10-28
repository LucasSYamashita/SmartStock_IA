// functions/src/index.ts
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import type { Request, Response } from "express";
import { VertexAI } from "@google-cloud/vertexai";

const REGION = "southamerica-east1";

// Firebase Admin
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ===== Vertex AI (Gemini) =====
const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
const VERTEX_LOCATION = "us-central1";
const CONFIG_MODEL =
  (functions.config().gemini && functions.config().gemini.model) || "";
const CHAT_MODEL = CONFIG_MODEL || "gemini-2.5-flash";

const vertex = new VertexAI({ project: PROJECT_ID, location: VERTEX_LOCATION });
const chatModel = vertex.getGenerativeModel({ model: CHAT_MODEL });

// ===== CORS / Auth helpers =====
function setCors(res: Response) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "content-type,x-tenant-id,x-role,x-uid");
  res.set("Access-Control-Allow-Methods", "POST,GET,OPTIONS");
}

function getAuthContext(req: Request) {
  return {
    tenantId: (req.header("x-tenant-id") || "default").toString(),
    role: (req.header("x-role") || "viewer").toString(),
    uid: (req.header("x-uid") || "anon").toString(),
  };
}

// ===== Firestore helpers =====
type MoveType = "entrada" | "saida";

function prodRef(t: string, p: string) {
  return db.collection("tenants").doc(t).collection("produtos").doc(p);
}
function movCol(t: string) {
  return db.collection("tenants").doc(t).collection("movimentos");
}

async function findProductByName(tenantId: string, name: string) {
  const lower = name.trim().toLowerCase();
  const col = db.collection("tenants").doc(tenantId).collection("produtos");

  let snap = await col.where("nomeLower", "==", lower).limit(1).get();
  if (!snap.empty) {
    const doc = snap.docs[0];
    const data = doc.data() as any;
    if (!data.nomeLower && (data.nome || data.Nome)) {
      await doc.ref.update({
        nomeLower: String(data.nome ?? data.Nome).toLowerCase().trim(),
      });
    }
    return { id: doc.id, ref: doc.ref, data };
  }

  snap = await col.where("nome", "==", name.trim()).limit(1).get();
  if (!snap.empty) {
    const doc = snap.docs[0];
    const data = doc.data() as any;
    if (!data.nomeLower && (data.nome || data.Nome)) {
      await doc.ref.update({
        nomeLower: String(data.nome ?? data.Nome).toLowerCase().trim(),
      });
    }
    return { id: doc.id, ref: doc.ref, data };
  }

  try {
    snap = await col
      .orderBy("nomeLower")
      .startAt([lower])
      .endAt([`${lower}\uf8ff`])
      .limit(1)
      .get();
    if (!snap.empty) {
      const doc = snap.docs[0];
      const data = doc.data() as any;
      if (!data.nomeLower && (data.nome || data.Nome)) {
        await doc.ref.update({
          nomeLower: String(data.nome ?? data.Nome).toLowerCase().trim(),
        });
      }
      return { id: doc.id, ref: doc.ref, data };
    }
  } catch { /* ignore */ }

  const sample = await col.limit(50).get();
  for (const d of sample.docs) {
    const data = d.data() as any;
    const n = String(data.nome ?? data.Nome ?? "").toLowerCase().trim();
    if (n === lower) {
      if (!data.nomeLower && (data.nome || data.Nome)) {
        await d.ref.update({ nomeLower: n });
      }
      return { id: d.id, ref: d.ref, data };
    }
  }
  return null;
}

/** Cria produto SEMPRE com quantidade 0. A entrada soma depois, na transação. */
async function ensureProduct(
  tenantId: string,
  name: string,
  _ignoreInitialQty: number = 0,
  uid: string = "chat-act"
) {
  const existing = await findProductByName(tenantId, name);
  if (existing) return { ...existing, created: false };

  const col = db.collection("tenants").doc(tenantId).collection("produtos");
  const doc = col.doc();
  const now = admin.firestore.FieldValue.serverTimestamp();

  const data = {
    nome: name,
    nomeLower: name.toLowerCase().trim(),
    quantidade: 0, // <- nasce zerado para evitar duplicação
    estoqueMinimo: 0,
    preco: 0,
    ativo: true,
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
    updatedBy: uid,
  };
  await doc.set(data);
  return { id: doc.id, ref: doc, data, created: true as const };
}

async function executeAction(args: {
  tenantId: string;
  uid: string;
  role: string;
  acao: "entrada" | "saida" | "relatorio";
  produto: string;
  quantidade?: number;
  mes?: number;
  allowCreateMissing?: boolean;
  preco?: number;   // opcional: definir/atualizar preço
  minimo?: number;  // opcional: definir/atualizar estoqueMinimo
}) {
  const {
    tenantId, uid, role, acao, produto, quantidade, mes,
    allowCreateMissing, preco, minimo,
  } = args;

  if (!tenantId) throw new Error("tenantId obrigatório");
  if (!acao || !produto) throw new Error("acao e produto obrigatórios");

  const canWrite = role === "staff" || role === "admin";

  if (acao === "entrada" || acao === "saida") {
    if (!canWrite) throw new Error("Sem permissão para movimentar estoque.");
    const q = Number(quantidade || 0);
    if (!Number.isFinite(q) || q <= 0) throw new Error("quantidade inválida.");

    if (acao === "entrada") {
      // cria se necessário
      const ensured = allowCreateMissing
        ? await ensureProduct(tenantId, produto, 0, uid)
        : await findProductByName(tenantId, produto);

      const prod = ensured || (await findProductByName(tenantId, produto));
      if (!prod) throw new Error(`Produto "${produto}" não encontrado.`);

      const pRef = prodRef(tenantId, prod!.id);

      // aplica preco/minimo (se enviados)
      if (typeof preco === "number" || Number.isInteger(minimo)) {
        const updates: any = {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: uid,
        };
        if (typeof preco === "number") updates.preco = Math.max(0, preco);
        if (Number.isInteger(minimo)) updates.estoqueMinimo = Math.max(0, minimo as number);
        await pRef.set(updates, { merge: true });
      }

      const mRef = movCol(tenantId).doc();
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(pRef);
        if (!snap.exists) throw new Error("Produto inexistente");
        const curr = Number((snap.data() as any)?.quantidade ?? 0);
        const next = curr + q; // soma uma única vez

        tx.update(pRef, {
          quantidade: next,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: uid,
        });
        tx.set(mRef, {
          tipo: "entrada",
          produtoId: prod!.id,
          usuarioId: uid,
          quantidade: q,
          motivo: "compra",
          origem: "chat",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      const extra: string[] = [];
      if (typeof preco === "number") extra.push(`preço ajustado para ${preco}`);
      if (Number.isInteger(minimo)) extra.push(`mínimo ${minimo}`);

      return {
        ok: true,
        created: (ensured as any)?.created ?? false,
        message:
          (ensured as any)?.created
            ? `Produto "${produto}" criado e entrada de ${q} un. registrada${extra.length ? ` (${extra.join(", ")})` : ""}.`
            : `Entrada de ${q} un. no produto "${produto}" registrada${extra.length ? ` (${extra.join(", ")})` : ""}.`,
      };
    }

    if (acao === "saida") {
      const prod = await findProductByName(tenantId, produto);
      if (!prod) throw new Error(`Produto "${produto}" não encontrado.`);
      const pRef = prodRef(tenantId, prod.id);
      const mRef = movCol(tenantId).doc();

      await db.runTransaction(async (tx) => {
        const snap = await tx.get(pRef);
        if (!snap.exists) throw new Error("Produto inexistente");
        const curr = Number((snap.data() as any)?.quantidade ?? 0);
        const next = curr - q;
        if (next < 0) throw new Error(`Estoque insuficiente: atual=${curr}, saída=${q}`);

        tx.update(pRef, {
          quantidade: next,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: uid,
        });
        tx.set(mRef, {
          tipo: "saida",
          produtoId: prod.id,
          usuarioId: uid,
          quantidade: q,
          motivo: "venda",
          origem: "chat",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      return { ok: true, message: `Saída de ${q} un. no produto "${produto}" registrada.` };
    }
  }

  if (acao === "relatorio") {
    const dt = new Date();
    const m = (mes && mes >= 1 && mes <= 12) ? mes : dt.getMonth() + 1;
    const y = dt.getFullYear();

    const prod = await findProductByName(tenantId, produto);
    if (!prod) throw new Error(`Produto "${produto}" não encontrado.`);

    const start = admin.firestore.Timestamp.fromDate(new Date(y, m - 1, 1));
    const end   = admin.firestore.Timestamp.fromDate(new Date(y, m, 1));

    const qSnap = await movCol(tenantId)
      .where("produtoId", "==", prod.id)
      .where("createdAt", ">=", start)
      .where("createdAt", "<", end)
      .get();

    let entradas = 0, saidas = 0;
    qSnap.forEach((d) => {
      const x = d.data() as any;
      if (x.tipo === "entrada") entradas += Number(x.quantidade || 0);
      if (x.tipo === "saida")   saidas   += Number(x.quantidade || 0);
    });

    const pSnap = await prodRef(tenantId, prod.id).get();
    const saldo = pSnap.exists
      ? Number((pSnap.data() as any)?.quantidade ?? (pSnap.data() as any)?.Quantidade ?? 0)
      : 0;

    return {
      ok: true,
      message: `Relatório ${(prod.data?.nome ?? prod.data?.Nome ?? produto)} - ${String(m).padStart(2,"0")}/${y}: entradas=${entradas}, saídas=${saidas}, saldo=${saldo}.`,
      month: m, year: y, entradas, saidas, saldo,
    };
  }

  throw new Error(`Ação desconhecida: ${acao}`);
}

// ===== LLM small helpers =====
function buildChatPrompt(
  system: string | undefined,
  messages: Array<{ role: "user" | "assistant" | "system"; content: string }>
) {
  const lines: string[] = [];
  if (system && system.trim()) lines.push(`SYSTEM:\n${system.trim()}`);
  for (const m of messages) lines.push(`${m.role}: ${m.content}`);
  return lines.join("\n");
}

function parseJsonLoose(raw: string): any {
  let s = (raw || "").trim();
  if (s.startsWith("```")) {
    s = s.replace(/^```[a-zA-Z]*\n?/, "").replace(/```$/, "").trim();
  }
  if (s.toLowerCase().startsWith("json")) s = s.substring(4).trim();
  return JSON.parse(s);
}

// ====== HTTP (diagnóstico + compat) ======
export const diag = functions.region(REGION).https.onRequest(async (_req, res) => {
  setCors(res);
  res.status(200).json({
    project: PROJECT_ID,
    location: VERTEX_LOCATION,
    runningModel: CHAT_MODEL,
    configModel: CONFIG_MODEL || null,
  });
});

// Legacy compat: /chatAct (us-central1) com CORS
export const chatAct = functions.region("us-central1").https.onRequest(async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");

  try {
    const { messages = [], system } = (req.body || {}) as {
      messages?: Array<{ role: "user" | "assistant" | "system"; content: string }>;
      system?: string;
    };

    const tenantId = (req.header("x-tenant-id") || "default").toString();
    const role     = (req.header("x-role") || "viewer").toString();
    const uid      = (req.header("x-uid") || "anon").toString();

    const dryRun = String(req.query?.dryRun ?? "true") === "true";
    const confirm = String(req.query?.confirm ?? "false") === "true";
    const createIfMissing = String(req.query?.createIfMissing ?? "false") === "true";

    const parserSys = `Você é o parser do SmartStock. Responda SOMENTE JSON puro.
{
  "acao": "entrada"|"saida"|"relatorio",
  "produto": "string",
  "quantidade": "int opcional (>0)",
  "mes": "int opcional (1..12)",
  "preco": "number opcional",
  "minimo": "int opcional"
}
Aceite variações como "preço 10", "10 reais", "min 2", "mínimo 2".`;

    const prompt = buildChatPrompt(system ? `${parserSys}\n${system}` : parserSys, messages);
    const r = await chatModel.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt }]}],
    });

    const raw = r?.response?.candidates
      ?.map((c:any) => (c?.content?.parts || []).map((p:any) => p?.text || "").join(""))
      .join("\n") || "{}";

    let parsed:any;
    try { parsed = parseJsonLoose(raw); }
    catch { return res.status(400).json({ ok:false, error:"Resposta não-JSON do parser.", raw }); }

    const { acao, produto, quantidade, mes } = parsed || {};
    const preco = (parsed && typeof parsed.preco === "number") ? parsed.preco : undefined;
    const minimo = (parsed && Number.isInteger(parsed.minimo)) ? parsed.minimo : undefined;

    if (!acao || !produto) return res.status(400).json({ ok:false, error:"Interpretação incompleta.", parsed, raw });

    if (dryRun) {
      const parts: string[] = [];
      if (typeof preco === "number") parts.push(`preço=${preco}`);
      if (Number.isInteger(minimo))  parts.push(`mínimo=${minimo}`);
      const extras = parts.length ? ` (${parts.join(", ")})` : "";

      const txt = acao === "relatorio"
        ? `Proposta: relatório do produto "${produto}" (mês: ${mes ?? "atual"}). Confirma?`
        : `Proposta: ${acao} de ${quantidade ?? "??"} un. em "${produto}"${extras}. Confirma?`;
      return res.status(200).json({ ok:true, parsed, assistant_text: txt, dryRun: true });
    }

    if (!confirm) {
      return res.status(400).json({ ok:false, error:"Confirmação ausente. Chame com ?confirm=true para executar.", parsed });
    }

    const exec = await executeAction({
      tenantId, uid, role, acao, produto, quantidade, mes,
      allowCreateMissing: createIfMissing,
      preco, minimo,
    });

    return res.status(200).json({ ok:true, parsed, result: exec, assistant_text: exec.message, dryRun:false, confirm:true });
  } catch (e:any) {
    return res.status(500).json({ ok:false, error:String(e?.message || e) });
  }
});

// HTTP chat (com CORS)
export const chat = functions.region(REGION).https.onRequest(async (req: Request, res: Response) => {
  if (req.method === "OPTIONS") { setCors(res); return res.status(204).send(""); }
  setCors(res);

  try {
    const { messages = [], system } = (req.body || {}) as {
      messages?: Array<{ role:"user"|"assistant"|"system"; content:string }>;
      system?: string;
    };
    const auth = getAuthContext(req);
    const baseSys = `Você é o assistente do SmartStock (tenant=${auth.tenantId}, role=${auth.role}). Seja objetivo.`;
    const prompt = buildChatPrompt(system ? `${baseSys}\n${system}` : baseSys, messages);

    const resp = await chatModel.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt || "Olá" }]}],
    });

    const text = resp?.response?.candidates
      ?.map((c:any) => (c?.content?.parts || []).map((p:any) => p?.text || "").join(""))
      .join("\n")?.trim() || "";

    return res.status(200).json({ text });
  } catch (e:any) {
    return res.status(500).json({ error: String(e?.message || e) });
  }
});

// HTTP act (com CORS)
export const act = functions.region(REGION).https.onRequest(async (req: Request, res: Response) => {
  if (req.method === "OPTIONS") { setCors(res); return res.status(204).send(""); }
  setCors(res);

  try {
    const dryRun = String(req.query?.dryRun ?? "true") === "true";
    const confirm = String(req.query?.confirm ?? "false") === "true";
    const createIfMissing = String(req.query?.createIfMissing ?? "false") === "true";

    const { messages = [], system } = (req.body || {}) as {
      messages?: Array<{ role:"user"|"assistant"|"system"; content:string }>;
      system?: string;
    };
    const { tenantId, role, uid } = getAuthContext(req);

    const parserSys = `Você é o parser do SmartStock. Responda SOMENTE JSON puro.
{
  "acao": "entrada"|"saida"|"relatorio",
  "produto": "string",
  "quantidade": "int opcional (>0)",
  "mes": "int opcional (1..12)",
  "preco": "number opcional",
  "minimo": "int opcional"
}
Aceite variações como "preço 10", "10 reais", "min 2", "mínimo 2".`;

    const prompt = buildChatPrompt(system ? `${parserSys}\n${system}` : parserSys, messages);
    const r = await chatModel.generateContent({ contents: [{ role:"user", parts:[{ text: prompt }]}] });

    const raw = r?.response?.candidates
      ?.map((c:any)=> (c?.content?.parts || []).map((p:any)=> p?.text || "").join(""))
      .join("\n") || "{}";

    let parsed:any;
    try { parsed = parseJsonLoose(raw); }
    catch { return res.status(400).json({ ok:false, error:"Resposta não-JSON do parser.", raw }); }

    const { acao, produto, quantidade, mes } = parsed || {};
    const preco = (parsed && typeof parsed.preco === "number") ? parsed.preco : undefined;
    const minimo = (parsed && Number.isInteger(parsed.minimo)) ? parsed.minimo : undefined;

    if (!acao || !produto) {
      return res.status(400).json({ ok:false, error:"Interpretação incompleta.", parsed, raw });
    }

    if (dryRun) {
      const parts: string[] = [];
      if (typeof preco === "number") parts.push(`preço=${preco}`);
      if (Number.isInteger(minimo))  parts.push(`mínimo=${minimo}`);
      const extras = parts.length ? ` (${parts.join(", ")})` : "";

      const txt = acao === "relatorio"
        ? `Proposta: relatório do produto "${produto}" (mês: ${mes ?? "atual"}). Confirma?`
        : `Proposta: ${acao} de ${quantidade ?? "??"} un. em "${produto}"${extras}. Confirma?`;
      return res.status(200).json({ ok:true, parsed, assistant_text: txt, dryRun:true });
    }

    if (!confirm) {
      return res.status(400).json({ ok:false, error:"Confirmação ausente. Chame com ?confirm=true para executar.", parsed });
    }

    const exec = await executeAction({
      tenantId, uid, role, acao, produto, quantidade, mes,
      allowCreateMissing: createIfMissing,
      preco, minimo,
    });

    return res.status(200).json({ ok:true, parsed, result: exec, assistant_text: exec.message, dryRun:false, confirm:true });
  } catch (e:any) {
    return res.status(500).json({ ok:false, error: String(e?.message || e) });
  }
});

// ====== Callables (recomendado no app) ======
export const chatCall = functions.region(REGION).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Faça login para usar o chat.");
  }

  const messages = (data?.messages || []) as Array<{ role:"user"|"assistant"|"system"; content:string }>;
  const system = String(data?.system ?? "");
  const tenantId = String(data?.tenantId ?? "default");
  const role = String(data?.role ?? "viewer");

  const baseSys = `Você é o assistente do SmartStock (tenant=${tenantId}, role=${role}). Seja objetivo.`;
  const prompt = buildChatPrompt(system ? `${baseSys}\n${system}` : baseSys, messages);

  const resp = await chatModel.generateContent({
    contents: [{ role:"user", parts:[{ text: prompt || "Olá" }]}],
  });

  const text = resp?.response?.candidates
    ?.map((c:any)=> (c?.content?.parts || []).map((p:any)=> p?.text || "").join(""))
    .join("\n")?.trim() || "";

  return { text };
});

export const actCall = functions.region(REGION).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Faça login para executar ações.");
  }

  const dryRun = Boolean(data?.dryRun ?? true);
  const confirm = Boolean(data?.confirm ?? false);
  const createIfMissing = Boolean(data?.createIfMissing ?? false);

  const messages = (data?.messages || []) as Array<{ role:"user"|"assistant"|"system"; content:string }>;
  const system = String(data?.system ?? "");
  const tenantId = String(data?.tenantId ?? "");
  const role = String(data?.role ?? "viewer");
  const uid = context.auth.uid!;

  const parserSys = `Você é o parser do SmartStock. Responda SOMENTE JSON puro.
{
  "acao": "entrada"|"saida"|"relatorio",
  "produto": "string",
  "quantidade": "int opcional (>0)",
  "mes": "int opcional (1..12)",
  "preco": "number opcional",
  "minimo": "int opcional"
}
Aceite variações como "preço 10", "10 reais", "min 2", "mínimo 2".`;

  const prompt = buildChatPrompt(system ? `${parserSys}\n${system}` : parserSys, messages);

  const r = await chatModel.generateContent({
    contents: [{ role:"user", parts:[{ text: prompt }]}],
  });

  const raw = r?.response?.candidates
    ?.map((c:any)=> (c?.content?.parts || []).map((p:any)=> p?.text || "").join(""))
    .join("\n") || "{}";

  let parsed:any;
  try { parsed = parseJsonLoose(raw); }
  catch {
    throw new functions.https.HttpsError("invalid-argument", "Resposta não-JSON do parser.");
  }

  const { acao, produto, quantidade, mes } = parsed || {};
  const preco = (parsed && typeof parsed.preco === "number") ? parsed.preco : undefined;
  const minimo = (parsed && Number.isInteger(parsed.minimo)) ? parsed.minimo : undefined;

  if (!acao || !produto) {
    throw new functions.https.HttpsError("invalid-argument", "Interpretação incompleta.");
  }

  if (dryRun) {
    const parts: string[] = [];
    if (typeof preco === "number") parts.push(`preço=${preco}`);
    if (Number.isInteger(minimo))  parts.push(`mínimo=${minimo}`);
    const extras = parts.length ? ` (${parts.join(", ")})` : "";

    const txt = acao === "relatorio"
      ? `Proposta: relatório do produto "${produto}" (mês: ${mes ?? "atual"}). Confirma?`
      : `Proposta: ${acao} de ${quantidade ?? "??"} un. em "${produto}"${extras}. Confirma?`;
    return { ok:true, parsed, assistant_text: txt, dryRun:true };
  }

  if (!confirm) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Confirmação ausente. Envie confirm=true para executar."
    );
  }

  const exec = await executeAction({
    tenantId, uid, role, acao, produto, quantidade, mes,
    allowCreateMissing: createIfMissing,
    preco, minimo,
  });

  return {
    ok: true,
    parsed,
    result: exec,
    assistant_text: exec.message,
    dryRun: false,
    confirm: true,
  };
});

// ===== Diagnósticos =====
export const whoami = functions.region(REGION).https.onRequest(async (_req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.json({
    projectId: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT,
    serviceAccountEmail: process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL || "unknown",
    firestoreDbPath: `projects/${process.env.GCLOUD_PROJECT}/databases/(default)`,
  });
});

export const firestoreProbe = functions.region(REGION).https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  try {
    const tenant = (req.query.tenantId as string) || "TENANT01";
    const ref = admin.firestore()
      .collection("tenants").doc(tenant)
      .collection("__diag__").doc("probe");

    await ref.set({
      wroteAt: admin.firestore.FieldValue.serverTimestamp(),
      note: "probe from Cloud Function",
    }, { merge: true });

    const snap = await ref.get();
    res.json({ ok: true, wrote: snap.exists, data: snap.data() });
  } catch (e:any) {
    res.status(500).json({ ok:false, error:String(e?.message || e), stack:e?.stack });
  }
});
