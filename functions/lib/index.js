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
exports.actCall = void 0;
// functions/src/index.ts
const admin = __importStar(require("firebase-admin"));
// v2 APIs
const https_1 = require("firebase-functions/v2/https");
const options_1 = require("firebase-functions/v2/options");
admin.initializeApp();
// defina a região e limites globais (pode ajustar)
(0, options_1.setGlobalOptions)({
    region: "southamerica-east1",
    maxInstances: 10,
});
const ok = (data) => ({ ok: true, ...data });
const fail = (code, message, data = {}) => new https_1.HttpsError(code, message, data);
// [id:req_xxx] do último texto do usuário
function parseRequestId(messages) {
    const lastUser = [...messages].reverse().find((m) => m.role === "user");
    if (!lastUser)
        return null;
    const m = /\[id:(.+?)\]/.exec(lastUser.content);
    return m?.[1] ?? null;
}
// extrai estado (produto, quantidade, preco, pular, confirmar) varrendo TUDO
function extractState(messages) {
    const lowAll = messages.map((m) => ({ ...m, content: m.content.toLowerCase() }));
    // preço
    let preco = null;
    for (const m of [...lowAll].reverse()) {
        const p1 = m.content.match(/\ba\s+(\d+(?:[.,]\d+)?)/);
        const p2 = m.content.match(/\bpor\s+(\d+(?:[.,]\d+)?)/);
        const p3 = m.content.match(/r\$\s*(\d+(?:[.,]\d+)?)/);
        const raw = (p1?.[1] ?? p2?.[1] ?? p3?.[1])?.replace(",", ".");
        if (raw && !Number.isNaN(parseFloat(raw))) {
            preco = parseFloat(raw);
            break;
        }
    }
    // quantidade
    let quantidade = null;
    for (const m of [...lowAll].reverse()) {
        const q = m.content.match(/(^|\s)(\d+)(\s|$)/);
        if (q) {
            const n = parseInt(q[2], 10);
            if (n > 0) {
                quantidade = n;
                break;
            }
        }
    }
    // produto
    let produto = null;
    for (const m of [...lowAll].reverse()) {
        const pA = m.content.match(/entrada\s+(?:de\s+)?([\p{L}\- ]+)/u);
        const pB = m.content.match(/\bem\s+([\p{L}\- ]+)/u);
        const pC = m.content.match(/\bde\s+([\p{L}\- ]+)/u);
        const cand = (pA?.[1] ?? pB?.[1] ?? pC?.[1])?.trim();
        if (cand) {
            produto = cand.replace(/\s+$/g, "").replace(/\s+/g, " ");
            break;
        }
    }
    const skipPreco = lowAll.some((m) => /\bpular\b/.test(m.content));
    const confirmar = lowAll.some((m) => /\bconfirma(r|do)?\b|\bok\b/.test(m.content));
    return { produto, quantidade, preco, skipPreco, confirmar };
}
exports.actCall = (0, https_1.onCall)(async (request) => {
    try {
        const data = request.data;
        const tenantId = String(data?.tenantId || "");
        const role = String(data?.role || "viewer"); // apenas informativo
        const messages = (data?.messages || []);
        const dryRun = Boolean(data?.dryRun);
        if (!tenantId)
            throw fail("invalid-argument", "missing-tenantId");
        if (!messages?.length)
            throw fail("invalid-argument", "missing-messages");
        if (!request.auth?.uid)
            throw fail("unauthenticated", "auth-required");
        const { produto, quantidade, preco, skipPreco, confirmar } = extractState(messages);
        const requestId = parseRequestId(messages);
        const db = admin.firestore();
        // etapa 1: precisa do produto
        if (!produto) {
            throw fail("invalid-argument", "Interpretação incompleta.", {
                assistant_text: "Não entendi o produto. Diga, por ex.: entrada de coca-cola.",
                want: "produto",
            });
        }
        // etapa 2: peça quantidade
        if (!quantidade) {
            const assistant_text = `Ok. Criar/usar o produto "${produto}". Quantas unidades?`;
            return ok({ assistant_text, next: "quantidade", parsed: { produto } });
        }
        // etapa 3: peça preço (ou aceitar 'pular')
        if (preco == null && !skipPreco) {
            const assistant_text = `Perfeito: ${quantidade} un. em "${produto}". Quer informar o preço? (ex.: a 5,50) — ou diga "pular".`;
            return ok({ assistant_text, next: "preco", parsed: { produto, quantidade } });
        }
        // etapa 4: confirmação
        if (!confirmar) {
            const precoTxt = (preco != null) ? ` a ${preco}` : "";
            const assistant_text = `Proposta: entrada de ${quantidade} un. em "${produto}"${precoTxt}. Confirmar?`;
            return ok({ assistant_text, next: "confirm", parsed: { produto, quantidade, preco } });
        }
        // dry-run
        if (dryRun) {
            const assistant_text = "Simulação ok (dry-run). Nada foi gravado.";
            return ok({ assistant_text, result: { produto, quantidade, preco, requestId } });
        }
        // idempotência
        if (requestId) {
            const dupe = await db.collection("tenants")
                .doc(tenantId)
                .collection("movimentos")
                .where("requestId", "==", requestId)
                .limit(1)
                .get();
            if (!dupe.empty) {
                return ok({
                    assistant_text: "Operação já registrada anteriormente (idempotente).",
                    result: { produto, quantidade, preco, requestId, reused: true },
                });
            }
        }
        // garantir produto (quantidade 0, estoqueMinimo 1)
        const nomeLower = String(produto).toLowerCase();
        const now = admin.firestore.FieldValue.serverTimestamp();
        const prodSnap = await db.collection("tenants").doc(tenantId)
            .collection("produtos")
            .where("nomeLower", "==", nomeLower)
            .limit(1)
            .get();
        let prodId;
        let prodNome = produto;
        if (prodSnap.empty) {
            const created = await db.collection("tenants").doc(tenantId)
                .collection("produtos")
                .add({
                nome: prodNome,
                nomeLower,
                categoria: "",
                sku: "",
                preco: preco ?? 0,
                quantidade: 0,
                estoqueMinimo: 1,
                ativo: true,
                createdAt: now,
                createdBy: request.auth.uid,
                updatedAt: now,
                updatedBy: request.auth.uid,
            });
            prodId = created.id;
        }
        else {
            const doc = prodSnap.docs[0];
            prodId = doc.id;
            prodNome = doc.get("nome") || prodNome;
        }
        // registrar movimento de entrada
        await db.collection("tenants").doc(tenantId)
            .collection("movimentos")
            .add({
            tipo: "entrada",
            quantidade,
            produtoId: prodId,
            produtoNome: prodNome,
            usuarioId: request.auth.uid,
            origem: "chat",
            motivo: "compra",
            preco: preco ?? null,
            requestId: requestId ?? null,
            createdAt: now,
        });
        const assistant_text = (preco != null)
            ? `✅ Entrada de ${quantidade} un. em "${prodNome}" registrada (preço ${preco}).`
            : `✅ Entrada de ${quantidade} un. em "${prodNome}" registrada.`;
        return ok({
            assistant_text,
            result: { produto: prodNome, quantidade, preco, requestId },
        });
    }
    catch (err) {
        if (err instanceof https_1.HttpsError)
            throw err;
        console.error(err);
        throw new https_1.HttpsError("internal", "Falha interna.", { detail: String(err?.message ?? err) });
    }
});
