"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.firestoreProbe = exports.whoami = exports.parseStockCommand = exports.act = exports.chat = exports.diag = void 0;
// functions/src/index.ts
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const vertexai_1 = require("@google-cloud/vertexai");
// ====== CONFIG ======
const REGION = "southamerica-east1";
// Admin SDK
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
// Vertex config (usa ADC do Cloud Functions)
const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
const VERTEX_LOCATION = "us-central1";
// Modelo (firebase functions:config:set gemini.model="gemini-2.5-flash")
const CONFIG_MODEL = (functions.config().gemini && functions.config().gemini.model) || "";
const CHAT_MODEL = CONFIG_MODEL || "gemini-2.5-flash";
const vertex = new vertexai_1.VertexAI({ project: PROJECT_ID, location: VERTEX_LOCATION });
const chatModel = vertex.getGenerativeModel({ model: CHAT_MODEL });
// ====== HTTP utils ======
function setCors(res) {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "content-type,x-tenant-id,x-role,x-uid");
    res.set("Access-Control-Allow-Methods", "POST,GET,OPTIONS");
}
function getAuthContext(req) {
    return {
        tenantId: (req.header("x-tenant-id") || "default").toString(),
        role: (req.header("x-role") || "viewer").toString(),
        uid: (req.header("x-uid") || "anon").toString(),
    };
}
function prodRef(t, p) {
    return db.collection("tenants").doc(t).collection("produtos").doc(p);
}
function movCol(t) {
    return db.collection("tenants").doc(t).collection("movimentos");
}
async function findProductByName(tenantId, name) {
    const lower = name.trim().toLowerCase();
    const col = db.collection("tenants").doc(tenantId).collection("produtos");
    let snap = await col.where("nomeLower", "==", lower).limit(1).get();
    if (!snap.empty) {
        const doc = snap.docs[0];
        const data = doc.data();
        if (!data.nomeLower && (data.nome || data.Nome)) {
            await doc.ref.update({ nomeLower: String(data.nome ?? data.Nome).toLowerCase().trim() });
        }
        return { id: doc.id, ref: doc.ref, data };
    }
    snap = await col.where("nome", "==", name.trim()).limit(1).get();
    if (!snap.empty) {
        const doc = snap.docs[0];
        const data = doc.data();
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
            const data = doc.data();
            if (!data.nomeLower && (data.nome || data.Nome)) {
                await doc.ref.update({ nomeLower: String(data.nome ?? data.Nome).toLowerCase().trim() });
            }
            return { id: doc.id, ref: doc.ref, data };
        }
    }
    catch { }
    const sample = await col.limit(50).get();
    for (const d of sample.docs) {
        const data = d.data();
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
async function ensureProduct(tenantId, name, initialQty = 0) {
    const existing = await findProductByName(tenantId, name);
    if (existing)
        return { ...existing, created: false };
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
    return { id: doc.id, ref: doc, data, created: true };
}
async function executeAction(args) {
    const { tenantId, uid, role, acao, produto, quantidade, mes, allowCreateMissing } = args;
    if (!tenantId)
        throw new Error("tenantId obrigatório");
    if (!acao || !produto)
        throw new Error("acao e produto obrigatórios");
    const canWrite = role === "staff" || role === "admin";
    if (acao === "entrada" || acao === "saida") {
        if (!canWrite)
            throw new Error("Sem permissão para movimentar estoque.");
        const q = Number(quantidade || 0);
        if (!Number.isFinite(q) || q <= 0)
            throw new Error("quantidade inválida.");
        if (acao === "entrada") {
            // 👇 cria se não existir e se foi autorizado
            const ensured = allowCreateMissing ? await ensureProduct(tenantId, produto, q) : await findProductByName(tenantId, produto);
            const prod = ensured || await findProductByName(tenantId, produto);
            if (!prod)
                throw new Error(`Produto "${produto}" não encontrado.`);
            const pRef = prodRef(tenantId, prod.id);
            const mRef = movCol(tenantId).doc();
            await db.runTransaction(async (tx) => {
                const snap = await tx.get(pRef);
                if (!snap.exists)
                    throw new Error("Produto inexistente");
                const curr = Number(snap.data()?.quantidade ?? 0);
                // se criou com initialQty=q, aqui ainda somamos q (estoque final = curr + q)
                const next = curr + q;
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
                    motivo: "compra",
                    origem: "chat",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            });
            return {
                ok: true,
                created: ensured?.created ?? false,
                message: ensured?.created
                    ? `🆕 Produto "${produto}" criado e entrada de ${q} un. registrada.`
                    : `✅ entrada de ${q} un. no produto "${produto}" registrada.`,
            };
        }
        if (acao === "saida") {
            const prod = await findProductByName(tenantId, produto);
            if (!prod)
                throw new Error(`Produto "${produto}" não encontrado.`);
            const pRef = prodRef(tenantId, prod.id);
            const mRef = movCol(tenantId).doc();
            await db.runTransaction(async (tx) => {
                const snap = await tx.get(pRef);
                if (!snap.exists)
                    throw new Error("Produto inexistente");
                const curr = Number(snap.data()?.quantidade ?? 0);
                const next = curr - q;
                if (next < 0)
                    throw new Error(`Estoque insuficiente: atual=${curr}, saída=${q}`);
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
        if (!prod)
            throw new Error(`Produto "${produto}" não encontrado.`);
        const start = admin.firestore.Timestamp.fromDate(new Date(y, m - 1, 1));
        const end = admin.firestore.Timestamp.fromDate(new Date(y, m, 1));
        const qSnap = await movCol(tenantId)
            .where("produtoId", "==", prod.id)
            .where("createdAt", ">=", start)
            .where("createdAt", "<", end)
            .get();
        let entradas = 0, saidas = 0;
        qSnap.forEach((d) => {
            const x = d.data();
            if (x.tipo === "entrada")
                entradas += Number(x.quantidade || 0);
            if (x.tipo === "saida")
                saidas += Number(x.quantidade || 0);
        });
        const pSnap = await prodRef(tenantId, prod.id).get();
        const saldo = pSnap.exists ? Number(pSnap.data()?.quantidade ?? pSnap.data()?.Quantidade ?? 0) : 0;
        return {
            ok: true,
            message: `Relatório ${(prod.data?.nome ?? prod.data?.Nome ?? produto)} - ${String(m).padStart(2, "0")}/${y}: entradas=${entradas}, saídas=${saidas}, saldo=${saldo}.`,
            month: m, year: y, entradas, saidas, saldo,
        };
    }
    throw new Error(`Ação desconhecida: ${acao}`);
}
// ====== LLM helpers ======
function buildChatPrompt(system, messages) {
    const lines = [];
    if (system && system.trim())
        lines.push(`SYSTEM:\n${system.trim()}`);
    for (const m of messages)
        lines.push(`${m.role}: ${m.content}`);
    return lines.join("\n");
}
function parseJsonLoose(raw) {
    let s = (raw || "").trim();
    if (s.startsWith("```")) {
        s = s.replace(/^```[a-zA-Z]*\n?/, "").replace(/```$/, "").trim();
    }
    if (s.toLowerCase().startsWith("json"))
        s = s.substring(4).trim();
    return JSON.parse(s);
}
// ====== Endpoints ======
// Diagnóstico
exports.diag = functions.region(REGION).https.onRequest(async (_req, res) => {
    setCors(res);
    res.status(200).json({
        project: PROJECT_ID,
        location: VERTEX_LOCATION,
        runningModel: CHAT_MODEL,
        configModel: CONFIG_MODEL || null,
    });
});
// Chat livre
exports.chat = functions.region(REGION).https.onRequest(async (req, res) => {
    if (req.method === "OPTIONS") {
        setCors(res);
        return res.status(204).send("");
    }
    setCors(res);
    try {
        const { messages = [], system } = (req.body || {});
        const auth = getAuthContext(req);
        const baseSys = `Você é o assistente do SmartStock (tenant=${auth.tenantId}, role=${auth.role}). Seja objetivo.`;
        const prompt = buildChatPrompt(system ? `${baseSys}\n${system}` : baseSys, messages);
        const resp = await chatModel.generateContent({
            contents: [{ role: "user", parts: [{ text: prompt || "Olá" }] }],
        });
        const text = resp?.response?.candidates?.[0]?.content?.parts?.map((p) => p?.text || "").join("") || "";
        return res.status(200).json({ text });
    }
    catch (e) {
        return res.status(500).json({ error: String(e?.message || e) });
    }
});
// Interpretar & Executar (dryRun/confirm/createIfMissing)
exports.act = functions.region(REGION).https.onRequest(async (req, res) => {
    if (req.method === "OPTIONS") {
        setCors(res);
        return res.status(204).send("");
    }
    setCors(res);
    const dryRun = String(req.query?.dryRun ?? "true") === "true";
    const confirm = String(req.query?.confirm ?? "false") === "true";
    // 👇 NOVO: habilita criação automática de produto quando acao=entrada
    const createIfMissing = String(req.query?.createIfMissing ?? "false") === "true";
    try {
        const { messages = [], system } = (req.body || {});
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
        const raw = r?.response?.candidates?.[0]?.content?.parts?.map((p) => p?.text || "").join("") || "{}";
        let parsed;
        try {
            parsed = parseJsonLoose(raw);
        }
        catch {
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
    }
    catch (e) {
        return res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
});
// parseStockCommand (callable)
exports.parseStockCommand = functions.region(REGION).https.onCall(async (data, context) => {
    if (!context.auth)
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    const text = String(data?.text ?? "").trim();
    const locale = String(data?.locale ?? "pt-BR");
    if (!text)
        throw new functions.https.HttpsError("invalid-argument", "Campo 'text' é obrigatório.");
    const sys = `Você é um parser de comandos de estoque. Responda SOMENTE JSON válido:
{
  "operations": [
    {"tipo":"entrada"|"saida","quantidade":int>0,"produtoNome":"string","motivo":"string opcional"}
  ]
}
Idioma: ${locale}. Não invente quantidade.`;
    const resp = await chatModel.generateContent({
        contents: [{ role: "user", parts: [{ text: `SYSTEM:\n${sys}\n\nUSER:\n${text}` }] }],
    });
    const raw = resp?.response?.candidates?.[0]?.content?.parts?.map((p) => p?.text || "").join("") || "{}";
    let out;
    try {
        out = parseJsonLoose(raw);
    }
    catch {
        throw new functions.https.HttpsError("internal", "Resposta não-JSON da IA.");
    }
    const ops = Array.isArray(out?.operations) ? out.operations : [];
    const clean = ops
        .filter((o) => (o?.tipo === "entrada" || o?.tipo === "saida") &&
        Number.isInteger(o?.quantidade) && o.quantidade > 0 &&
        typeof o?.produtoNome === "string" && o.produtoNome.trim().length > 0)
        .map((o) => ({
        tipo: o.tipo,
        quantidade: o.quantidade,
        produtoNome: String(o.produtoNome).trim(),
        motivo: (typeof o.motivo === "string" && o.motivo.trim().length) ? String(o.motivo).trim() : undefined,
    }));
    return { operations: clean };
});
// whoami
exports.whoami = functions.region(REGION).https.onRequest(async (_req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.json({
        projectId: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT,
        serviceAccountEmail: process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL || "unknown",
        firestoreDbPath: `projects/${process.env.GCLOUD_PROJECT}/databases/(default)`,
    });
});
// probe
exports.firestoreProbe = functions.region(REGION).https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    try {
        const tenant = req.query.tenantId || "TENANT01";
        const ref = admin.firestore()
            .collection("tenants").doc(tenant)
            .collection("__diag__").doc("probe");
        await ref.set({
            wroteAt: admin.firestore.FieldValue.serverTimestamp(),
            note: "probe from Cloud Function",
        }, { merge: true });
        const snap = await ref.get();
        res.json({ ok: true, wrote: snap.exists, data: snap.data() });
    }
    catch (e) {
        res.status(500).json({ ok: false, error: String(e?.message || e), stack: e?.stack });
    }
});
