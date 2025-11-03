// functions/src/index.ts
import * as admin from "firebase-admin";
import {
  onCall,
  HttpsError,
  CallableRequest,
} from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import * as logger from "firebase-functions/logger";

setGlobalOptions({
  region: "southamerica-east1",
  maxInstances: 5,
});

admin.initializeApp();

/* ===================== Tipos ===================== */
export type ActCallInput = {
  requestId: string; // idempotência vindo do app
  tenantId: string;
  role: string;      // 'admin' | 'staff' | 'viewer'
  text: string;
};

export type ActCallOutput = {
  requestId: string;
  ok: boolean;
  message: string;
  intent?: "entrada" | "desconhecido";
  parsed?: {
    produto?: string;
    quantidade?: number;
    preco?: number;
  };
};

/* ============== Parser simples de “entrada …” ============== */
function parseEntrada(text: string) {
  const t = text.toLowerCase().trim().replace(/\s+/g, " ");
  if (!t.startsWith("entrada ")) return null;

  const rest = t.substring("entrada ".length).trim();
  const re =
    /^(?<produto>.+?)(?:\s+(?<qtd>\d+))?(?:\s+a\s+(?<preco>\d+[.,]?\d*))?$/i;
  const m = rest.match(re);
  if (!m || !m.groups) return null;

  const produto = m.groups.produto?.trim().replace(/["']/g, "");
  const qtdRaw = m.groups.qtd?.trim();
  const precoRaw = m.groups.preco?.trim();

  const quantidade = qtdRaw ? Number(qtdRaw) : undefined;

  let preco: number | undefined = undefined;
  if (precoRaw) {
    const norm = precoRaw.replace(",", ".");
    const n = Number(norm);
    if (!Number.isNaN(n)) preco = n;
  }

  if (!produto) return null;
  return { produto, quantidade, preco };
}

/* ===================== Callable (Gen 2) ===================== */
export const actCallV2 = onCall<ActCallInput, ActCallOutput>(
  { timeoutSeconds: 60, memory: "512MiB" }, // opções por função
  (req: CallableRequest<ActCallInput>): ActCallOutput => {
    try {
      const data = (req.data ?? {}) as Partial<ActCallInput>;

      const requestId = String(data.requestId ?? "");
      const tenantId = String(data.tenantId ?? "");
      const role = String(data.role ?? "");
      const text = String(data.text ?? "");

      if (!requestId || !tenantId || !role || !text) {
        logger.warn("invalid-argument", { requestId, tenantId, role, text });
        throw new HttpsError("invalid-argument", "Interpretação incompleta.");
      }

      logger.info("actCallV2 received", { requestId, tenantId, role, text });

      // —— parser “entrada …”
      const entrada = parseEntrada(text);
      if (entrada) {
        const { produto, quantidade, preco } = entrada;

        let msg = `Proposta: entrada em "${produto}"`;
        if (quantidade !== undefined) msg += ` de ${quantidade} un.`;
        if (preco !== undefined) msg += ` a ${preco.toFixed(2)}`;
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
        message:
          'Não entendi. Tente: "entrada coca-cola", "entrada coca-cola 10" ou "entrada coca-cola 10 a 5,50".',
        intent: "desconhecido",
      };
    } catch (err: any) {
      logger.error("actCallV2 error", { err });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError(
        "internal",
        "Falha interna.",
        String(err?.message ?? err)
      );
    }
  }
);
