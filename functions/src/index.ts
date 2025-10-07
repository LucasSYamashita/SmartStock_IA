// functions/src/index.ts
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import type { Request, Response } from "express";
import { VertexAI } from "@google-cloud/vertexai";

// ====== CONFIG ======
const REGION = "southamerica-east1";

// Admin SDK
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// Vertex config (usa ADC do Cloud Functions)
const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
const VERTEX_LOCATION = "us-central1";

// Modelo (firebase functions:config:set gemini.model="gemini-2.5-flash")
const CONFIG_MODEL = (functions.config().gemini && functions.config().gemini.model) || "";
const CHAT_MODEL = CONFIG_MODEL || "gemini-2.5-flash";

const vertex = new VertexAI({ project: PROJECT_ID, location: VERTEX_LOCATION });
const chatModel = vertex.getGenerativeModel({ model: CHAT_MODEL });

// ====== HTTP utils ======
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

// ====== Helpers Firestore ======
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
      await doc.ref.update({ nomeLower: String(data.nome ?? data.Nome).toLowerCase().trim() });
    }
    return { id: doc.id, ref: doc.ref, data };
  }

  snap = await col.where("nome", "==", name.trim()).limit(1).get();
  if (!snap.empty) {
    const doc = snap.docs[0];
    const data = doc.data() as any;
    if (!data.nomeLower && (data.nome || data.Nome)) {
      await doc.ref.update({ nomeLower: String(data.nome ?? data.Nome).toLowerCase().trim() });
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
        await doc.ref.update({ nomeLower: String(data.nome ?? data.Nome).toLowerCase().trim() });
      }
      return { id: doc.id, ref: doc.ref, data };
    }
  } catch {}

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

async function ensureProduct(
  tenantId: string,
  name: string,
  initialQty: number = 0
) {
  const existing = await findProductByName(tenantId, name);
  if (existing) return { ...existing, created: false };

  const col = db.collection("tenants").doc(tenantId).collection("produtos");
  const doc = col.doc();
  const now = admin.firestore.FieldValue.serverTimestamp();

  const data = {
    nome: name,
    nomeLower: name.toLowerCase().trim(),
    quantidade: Math.max(0, initialQty),
    estoqueMinimo: 0,
    preco: 0,
    ativo: true,
    createdAt: now,
    updatedAt: now,
    createdBy: "chat-act",
  };
  await doc.set(data);
  return { id: doc.id, ref: doc, data, created: true as const };
}

async function executeAction(args: {
  tenantId: string; uid: string; role: string;
  acao: "entrada" | "saida" | "relatorio";
  produto: string; quantidade?: number; mes?: number;
  allowCreateMissing?: boolean;
}) {
  const { tenantId, uid, role, acao, produto, quantidade, mes, allowCreateMissing } = args;
  if (!tenantId) throw new Error("tenantId obrigatório");
  if (!acao || !produto) throw new Error("acao e produto obrigatórios");

  const canWrite = role === "staff" || role === "admin";

  if (acao === "entrada" || acao === "saida") {
    if (!canWrite) throw new Error("Sem permissão para movimentar estoque.");
    const q = Number(quantidade || 0);
    if (!Number.isFinite(q) || q <= 0) throw new Error("quantidade inválida.");

    if (acao === "entrada") {
      // 👇 cria se não existir e se foi autorizado
      const ensured = allowCreateMissing ? await ensureProduct(tenantId, produto, q) : await findProductByName(tenantId, produto);
      const prod = ensured || await findProductByName(tenantId, produto);
      if (!prod) throw new Error(`Produto "${produto}" não encontrado.`);

      const pRef = prodRef(tenantId, prod!.id);
      const mRef = movCol(tenantId).doc();

      await db.runTransaction(async (tx) => {
        const snap = await tx.get(pRef);
        if (!snap.exists) throw new Error("Produto inexistente");
        const curr = Number((snap.data() as any)?.quantidade ?? 0);
        // se criou com initialQty=q, aqui ainda somamos q (estoque final = curr + q)
        const next = curr + q;

        tx.update(pRef, {
          quantidade: next,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: uid,
        });
        tx.set(mRef, {
          tipo: acao,
          produtoId: prod!.id,
          usuarioId: uid,
          quantidade: q,
          motivo: "compra",
          origem: "chat",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      return {
        ok: true,
        created: (ensured as any)?.created ?? false,
        message: (ensured as any)?.created
          ? `🆕 Produto "${produto}" criado e entrada de ${q} un. registrada.`
          : `✅ entrada de ${q} un. no produto "${produto}" registrada.`,
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
          tipo: acao,
          produtoId: prod.id,
          usuarioId: uid,
          quantidade: q,
          motivo: "venda",
          origem: "chat",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      return {
        ok: true,
        message: `✅ saída de ${q} un. no produto "${produto}" registrada.`,
      };
    }
  }

  if (acao === "relatorio") {
    const dt = new Date();
    const m = (mes && mes >= 1 && mes <= 12) ? mes : dt.getMonth() + 1;
    const y = dt.getFullYear();

    const prod = await findProductByName(tenantId, produto);
    if (!prod) throw new Error(`Produto "${produto}" não encontrado.`);

    const start = admin.firestore.Timestamp.fromDate(new Date(y, m - 1, 1));
    const end = admin.firestore.Timestamp.fromDate(new Date(y, m, 1));

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
    const saldo = pSnap.exists ? Number((pSnap.data() as any)?.quantidade ?? (pSnap.data() as any)?.Quantidade ?? 0) : 0;

    return {
      ok: true,
      message: `Relatório ${(prod.data?.nome ?? prod.data?.Nome ?? produto)} - ${String(m).padStart(2,"0")}/${y}: entradas=${entradas}, saídas=${saidas}, saldo=${saldo}.`,
      month: m, year: y, entradas, saidas, saldo,
    };
  }

  throw new Error(`Ação desconhecida: ${acao}`);
}

// ====== LLM helpers ======
function buildChatPrompt(system: string | undefined, messages: Array<{role:"user"|"assistant"|"system"; content:string}>) {
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

// ====== Endpoints ======

// Diagnóstico
export const diag = functions.region(REGION).https.onRequest(async (_req, res) => {
  setCors(res);
  res.status(200).json({
    project: PROJECT_ID,
    location: VERTEX_LOCATION,
    runningModel: CHAT_MODEL,
    configModel: CONFIG_MODEL || null,
  });
});

// Chat livre
export const chat = functions.region(REGION).https.onRequest(async (req: Request, res: Response) => {
  if (req.method === "OPTIONS") { setCors(res); return res.status(204).send(""); }
  setCors(res);

  try {
    const { messages = [], system } = (req.body || {}) as {
      messages?: Array<{ role: "user" | "assistant" | "system"; content: string; }>;
      system?: string;
    };
    const auth = getAuthContext(req);
    const baseSys = `Você é o assistente do SmartStock (tenant=${auth.tenantId}, role=${auth.role}). Seja objetivo.`;

    const prompt = buildChatPrompt(system ? `${baseSys}\n${system}` : baseSys, messages);

    const resp = await chatModel.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt || "Olá" }] } ],
    });

    const text = resp?.response?.candidates?.[0]?.content?.parts?.map((p: any) => p?.text || "").join("") || "";
    return res.status(200).json({ text });
  } catch (e: any) {
    return res.status(500).json({ error: String(e?.message || e) });
  }
});

// Interpretar & Executar (dryRun/confirm/createIfMissing)
export const act = functions.region(REGION).https.onRequest(async (req: Request, res: Response) => {
  if (req.method === "OPTIONS") { setCors(res); return res.status(204).send(""); }
  setCors(res);

  const dryRun = String(req.query?.dryRun ?? "true") === "true";
  const confirm = String(req.query?.confirm ?? "false") === "true";
  // 👇 NOVO: habilita criação automática de produto quando acao=entrada
  const createIfMissing = String(req.query?.createIfMissing ?? "false") === "true";

  try {
    const { messages = [], system } = (req.body || {}) as {
      messages?: Array<{ role: "user" | "assistant" | "system"; content: string; }>;
      system?: string;
    };
    const { tenantId, role, uid } = getAuthContext(req);

    const parserSys = `Você é o parser do SmartStock. Responda SOMENTE JSON puro.
Schema:
{
  "acao": "entrada"|"saida"|"relatorio",
  "produto": "string",
  "quantidade": "int opcional (>0)",
  "mes": "int opcional (1..12)"
}
Se faltar quantidade, não crie entrada/saida.`;
    const prompt = buildChatPrompt(system ? `${parserSys}\n${system}` : parserSys, messages);

    const r = await chatModel.generateContent({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
    });

    const raw = r?.response?.candidates?.[0]?.content?.parts?.map((p: any) => p?.text || "").join("") || "{}";

    let parsed: any;
    try {
      parsed = parseJsonLoose(raw);
    } catch {
      return res.status(400).json({ ok: false, error: "Resposta não-JSON do parser.", raw });
    }

    const { acao, produto, quantidade, mes } = parsed || {};
    if (!acao || !produto) {
      return res.status(400).json({ ok: false, error: "Interpretação incompleta.", parsed, raw });
    }

    if (dryRun) {
      const txt = acao === "relatorio"
        ? `Proposta: relatório do produto "${produto}" (mês: ${mes ?? "atual"}). Confirma?`
        : `Proposta: ${acao} de ${quantidade ?? "??"} un. em "${produto}". Confirma?`;
      return res.status(200).json({ ok: true, parsed, assistant_text: txt, dryRun: true });
    }

    if (!confirm) {
      return res.status(400).json({
        ok: false,
        error: "Confirmação ausente. Chame com ?confirm=true para executar.",
        parsed,
      });
    }

    // 👇 Passa createIfMissing para a execução
    const exec = await executeAction({
      tenantId, uid, role, acao, produto, quantidade, mes,
      allowCreateMissing: createIfMissing,
    });

    return res.status(200).json({
      ok: true,
      parsed,
      result: exec,
      assistant_text: exec.message,
      dryRun: false,
      confirm: true,
    });
  } catch (e: any) {
    return res.status(500).json({ ok: false, error: String(e?.message || e) });
  }
});

// parseStockCommand (callable)
export const parseStockCommand = functions.region(REGION).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Faça login.");

  const text = String(data?.text ?? "").trim();
  const locale = String(data?.locale ?? "pt-BR");
  if (!text) throw new functions.https.HttpsError("invalid-argument", "Campo 'text' é obrigatório.");

  const sys =
`Você é um parser de comandos de estoque. Responda SOMENTE JSON válido:
{
  "operations": [
    {"tipo":"entrada"|"saida","quantidade":int>0,"produtoNome":"string","motivo":"string opcional"}
  ]
}
Idioma: ${locale}. Não invente quantidade.`;

  const resp = await chatModel.generateContent({
    contents: [{ role: "user", parts: [{ text: `SYSTEM:\n${sys}\n\nUSER:\n${text}` }]}],
  });

  const raw = resp?.response?.candidates?.[0]?.content?.parts?.map((p: any) => p?.text || "").join("") || "{}";
  let out: any;
  try {
    out = parseJsonLoose(raw);
  } catch {
    throw new functions.https.HttpsError("internal", "Resposta não-JSON da IA.");
  }

  const ops = Array.isArray(out?.operations) ? out.operations : [];
  const clean = ops
    .filter((o: any) =>
      (o?.tipo === "entrada" || o?.tipo === "saida") &&
      Number.isInteger(o?.quantidade) && o.quantidade > 0 &&
      typeof o?.produtoNome === "string" && o.produtoNome.trim().length > 0
    )
    .map((o: any) => ({
      tipo: o.tipo as MoveType,
      quantidade: o.quantidade as number,
      produtoNome: String(o.produtoNome).trim(),
      motivo: (typeof o.motivo === "string" && o.motivo.trim().length) ? String(o.motivo).trim() : undefined,
    }));

  return { operations: clean };
});

// whoami
export const whoami = functions.region(REGION).https.onRequest(async (_req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.json({
    projectId: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT,
    serviceAccountEmail: process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL || "unknown",
    firestoreDbPath: `projects/${process.env.GCLOUD_PROJECT}/databases/(default)`,
  });
});

// probe
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
  } catch (e: any) {
    res.status(500).json({ ok: false, error: String(e?.message || e), stack: e?.stack });
  }
});
