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
exports.parseStockCommand = exports.act = exports.chat = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const vertexai_1 = require("@google-cloud/vertexai");
const REGION = "southamerica-east1"; // região das Cloud Functions
const VERTEX_LOCATION = "us-central1"; // região do Vertex/Gemini (suporte amplo)
const VERTEX_PROJECT = process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    (process.env.FIREBASE_CONFIG && JSON.parse(process.env.FIREBASE_CONFIG).projectId) ||
    "";
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const vertex = new vertexai_1.VertexAI({ project: VERTEX_PROJECT, location: VERTEX_LOCATION });
// modelos
const CHAT_MODEL = "gemini-1.5-flash-002";
const PARSER_MODEL = CHAT_MODEL;
/* ---------------- HTTP/CORS utils ---------------- */
function setCors(res) {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "content-type,x-tenant-id,x-role,x-uid");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
}
function getAuthContext(req) {
    return {
        tenantId: (req.header("x-tenant-id") || "default").toString(),
        role: (req.header("x-role") || "viewer").toString(),
        uid: (req.header("x-uid") || "anon").toString(),
    };
}
async function findProductByName(tenantId, name) {
    const lower = name.trim().toLowerCase();
    const col = db.collection("tenants").doc(tenantId).collection("produtos");
    let snap = await col.where("nomeLower", "==", lower).limit(1).get();
    if (!snap.empty) {
        const doc = snap.docs[0];
        return { id: doc.id, ref: doc.ref, data: doc.data() };
    }
    snap = await col.where("nome", "==", name.trim()).limit(1).get();
    if (!snap.empty) {
        const doc = snap.docs[0];
        return { id: doc.id, ref: doc.ref, data: doc.data() };
    }
    return null;
}
function prodRef(t, p) {
    return db.collection("tenants").doc(t).collection("produtos").doc(p);
}
function movCol(t) {
    return db.collection("tenants").doc(t).collection("movimentos");
}
async function executeAction(args) {
    const { tenantId, uid, role, acao, produto, quantidade, mes } = args;
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
        const prod = await findProductByName(tenantId, produto);
        if (!prod)
            throw new Error(`Produto "${produto}" não encontrado.`);
        const pRef = prodRef(tenantId, prod.id);
        const mRef = movCol(tenantId).doc();
        await db.runTransaction(async (tx) => {
            const snap = await tx.get(pRef);
            if (!snap.exists)
                throw new Error("Produto inexistente");
            const curr = Number(snap.data()?.quantidade || 0);
            const next = acao === "entrada" ? curr + q : curr - q;
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
                motivo: acao === "entrada" ? "compra" : "venda",
                origem: "chat",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
        return {
            ok: true,
            message: `✅ ${acao} de ${q} un. no produto "${prod.data.nome || produto}" registrada.`,
        };
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
        const saldo = pSnap.exists ? Number(pSnap.data()?.quantidade || 0) : 0;
        return {
            ok: true,
            message: `Relatório ${prod.data.nome || produto} - ${String(m).padStart(2, "0")}/${y}: entradas=${entradas}, saídas=${saidas}, saldo=${saldo}.`,
            month: m, year: y, entradas, saidas, saldo,
        };
    }
    throw new Error(`Ação desconhecida: ${acao}`);
}
/* ---------------- Vertex helpers ---------------- */
async function vertexGenerateText(model, prompt) {
    const gen = vertex.getGenerativeModel({ model });
    const result = await gen.generateContent({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.3 },
    });
    return result.response.candidates?.[0]?.content?.parts
        ?.map((p) => p?.text || "")
        .join("") || "";
}
async function vertexGenerateJson(model, userText, system, schema) {
    const gen = vertex.getGenerativeModel({ model });
    const result = await gen.generateContent({
        contents: [
            { role: "user", parts: [{ text: `SYSTEM:\n${system}` }] },
            { role: "user", parts: [{ text: userText }] },
        ],
        generationConfig: {
            temperature: 0,
            responseMimeType: "application/json",
            responseSchema: schema,
        },
    });
    const txt = result.response.candidates?.[0]?.content?.parts
        ?.map((p) => p?.text || "")
        .join("") || "{}";
    return JSON.parse(txt);
}
/* ---------------- 1) CHAT (HTTP) ---------------- */
exports.chat = functions.region(REGION).https.onRequest(async (req, res) => {
    if (req.method === "OPTIONS") {
        setCors(res);
        res.status(204).send("");
        return;
    }
    setCors(res);
    const body = (req.body || {});
    const { messages = [], system } = body;
    const auth = getAuthContext(req);
    const baseSys = `Você é o assistente do SmartStock (tenant=${auth.tenantId}, role=${auth.role}).
Responda claro e objetivo. Quando fizer sentido, proponha JSON {acao:"entrada|saida|relatorio", produto, quantidade:int, mes?:int}.`;
    const prompt = [
        baseSys,
        system ? `\n${system}` : "",
        "\n\n",
        messages.map(m => `${m.role}: ${m.content}`).join("\n") || "Olá"
    ].join("");
    try {
        const text = await vertexGenerateText(CHAT_MODEL, prompt);
        res.status(200).json({ text });
    }
    catch (e) {
        res.status(500).json({ error: String(e?.message || e) });
    }
});
/* ---------------- 2) ACT (HTTP) ---------------- */
exports.act = functions.region(REGION).https.onRequest(async (req, res) => {
    if (req.method === "OPTIONS") {
        setCors(res);
        res.status(204).send("");
        return;
    }
    setCors(res);
    const body = (req.body || {});
    const { messages = [], system } = body;
    const { tenantId, role, uid } = getAuthContext(req);
    const parserPrompt = `Você é o parser do SmartStock. Retorne SOMENTE JSON válido e enxuto.
Campos: { acao:"entrada|saida|relatorio", produto:string, quantidade?:int>0, mes?:1-12 }.
Se faltar quantidade, não crie entrada/saida.`;
    const schema = {
        type: "object",
        properties: {
            acao: { type: "string", enum: ["entrada", "saida", "relatorio"] },
            produto: { type: "string" },
            quantidade: { type: "integer" },
            mes: { type: "integer" },
        },
        required: ["acao", "produto"],
        additionalProperties: false,
    };
    try {
        const textAll = messages.map(m => `${m.role}: ${m.content}`).join("\n") || "Olá";
        const parsed = await vertexGenerateJson(PARSER_MODEL, textAll, system ? `${parserPrompt}\n${system}` : parserPrompt, schema);
        const { acao, produto, quantidade, mes } = parsed || {};
        if (!acao || !produto) {
            res.status(400).json({ ok: false, error: "Interpretação incompleta.", parsed });
            return;
        }
        const exec = await executeAction({ tenantId, uid, role, acao, produto, quantidade, mes });
        res.status(200).json({ ok: true, parsed, result: exec, assistant_text: exec.message });
    }
    catch (e) {
        res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
});
/* ---------------- 3) parseStockCommand (Callable) ---------------- */
exports.parseStockCommand = functions.region(REGION).https.onCall(async (data, context) => {
    if (!context.auth)
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    const text = String(data?.text ?? "").trim();
    const locale = String(data?.locale ?? "pt-BR");
    if (!text)
        throw new functions.https.HttpsError("invalid-argument", "Campo 'text' é obrigatório.");
    const system = `Você é um parser de comandos de estoque. Responda SOMENTE JSON válido no schema abaixo.
Objetivo: dado um texto em ${locale}, detectar zero ou mais operações:
{ tipo:"entrada"|"saida", quantidade:int>0, produtoNome:string, motivo?:string }
Regra: não invente quantidades; se faltar, não crie operação.`;
    const schema = {
        type: "object",
        properties: {
            operations: {
                type: "array",
                items: {
                    type: "object",
                    properties: {
                        tipo: { type: "string", enum: ["entrada", "saida"] },
                        quantidade: { type: "integer", minimum: 1 },
                        produtoNome: { type: "string", minLength: 1 },
                        motivo: { type: "string" },
                    },
                    required: ["tipo", "quantidade", "produtoNome"],
                    additionalProperties: false,
                },
            },
        },
        required: ["operations"],
        additionalProperties: false,
    };
    const out = await vertexGenerateJson(PARSER_MODEL, text, system, schema);
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
//# sourceMappingURL=index.js.map