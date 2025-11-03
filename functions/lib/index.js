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
exports.actCallV2 = void 0;
// functions/src/index.ts
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const options_1 = require("firebase-functions/v2/options");
const logger = __importStar(require("firebase-functions/logger"));
(0, options_1.setGlobalOptions)({
    region: "southamerica-east1",
    maxInstances: 5,
});
admin.initializeApp();
/* ============== Parser simples de “entrada …” ============== */
function parseEntrada(text) {
    const t = text.toLowerCase().trim().replace(/\s+/g, " ");
    if (!t.startsWith("entrada "))
        return null;
    const rest = t.substring("entrada ".length).trim();
    const re = /^(?<produto>.+?)(?:\s+(?<qtd>\d+))?(?:\s+a\s+(?<preco>\d+[.,]?\d*))?$/i;
    const m = rest.match(re);
    if (!m || !m.groups)
        return null;
    const produto = m.groups.produto?.trim().replace(/["']/g, "");
    const qtdRaw = m.groups.qtd?.trim();
    const precoRaw = m.groups.preco?.trim();
    const quantidade = qtdRaw ? Number(qtdRaw) : undefined;
    let preco = undefined;
    if (precoRaw) {
        const norm = precoRaw.replace(",", ".");
        const n = Number(norm);
        if (!Number.isNaN(n))
            preco = n;
    }
    if (!produto)
        return null;
    return { produto, quantidade, preco };
}
/* ===================== Callable (Gen 2) ===================== */
exports.actCallV2 = (0, https_1.onCall)({ timeoutSeconds: 60, memory: "512MiB" }, // opções por função
(req) => {
    try {
        const data = (req.data ?? {});
        const requestId = String(data.requestId ?? "");
        const tenantId = String(data.tenantId ?? "");
        const role = String(data.role ?? "");
        const text = String(data.text ?? "");
        if (!requestId || !tenantId || !role || !text) {
            logger.warn("invalid-argument", { requestId, tenantId, role, text });
            throw new https_1.HttpsError("invalid-argument", "Interpretação incompleta.");
        }
        logger.info("actCallV2 received", { requestId, tenantId, role, text });
        // —— parser “entrada …”
        const entrada = parseEntrada(text);
        if (entrada) {
            const { produto, quantidade, preco } = entrada;
            let msg = `Proposta: entrada em "${produto}"`;
            if (quantidade !== undefined)
                msg += ` de ${quantidade} un.`;
            if (preco !== undefined)
                msg += ` a ${preco.toFixed(2)}`;
            msg += `. Confirmar?`;
            return {
                requestId,
                ok: true,
                message: msg,
                intent: "entrada",
                parsed: { produto, quantidade, preco },
            };
        }
        // —— fallback
        return {
            requestId,
            ok: true,
            message: 'Não entendi. Tente: "entrada coca-cola", "entrada coca-cola 10" ou "entrada coca-cola 10 a 5,50".',
            intent: "desconhecido",
        };
    }
    catch (err) {
        logger.error("actCallV2 error", { err });
        if (err instanceof https_1.HttpsError)
            throw err;
        throw new https_1.HttpsError("internal", "Falha interna.", String(err?.message ?? err));
    }
});
