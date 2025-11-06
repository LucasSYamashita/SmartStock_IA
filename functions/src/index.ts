import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";
import * as logger from "firebase-functions/logger";

setGlobalOptions({ region: "southamerica-east1", maxInstances: 5 });
admin.initializeApp();

/* ========= Tipos ========= */
export type ActCallInput = {
  requestId: string;
  tenantId: string;
  role: string;       // 'admin' | 'staff' | 'viewer'
  text: string;
};

export type ActCallOutput = {
  requestId: string;
  ok: boolean;
  message: string;
  intent?: "entrada" | "desconhecido";
  parsed?: { produto?: string; quantidade?: number; preco?: number };
};

/* ========= Parser “entrada …” ========= */
function parseEntrada(text: string) {
  const t = text.toLowerCase().trim().replace(/\s+/g, " ");
  if (!t.startsWith("entrada ")) return null;

  const rest = t.substring("entrada ".length).trim();

  type Hit = { produto: string; quantidade?: number; preco?: number };
  const tryParse = (
    m: RegExpMatchArray | null,
    produtoIdx: number,
    qtdIdx?: number,
    precoIdx?: number
  ): Hit | null => {
    if (!m) return null;
    const produto = (m[produtoIdx] ?? "").trim().replace(/["']/g, "");
    if (!produto) return null;

    let quantidade: number | undefined = undefined;
    if (qtdIdx !== undefined && m[qtdIdx]) {
      const q = Number(String(m[qtdIdx]).replace(",", "."));
      if (!Number.isNaN(q)) quantidade = q;
    }

    let preco: number | undefined = undefined;
    if (precoIdx !== undefined && m[precoIdx]) {
      const p = Number(String(m[precoIdx]).replace(",", "."));
      if (!Number.isNaN(p)) preco = p;
    }
    return { produto, quantidade, preco };
  };

  // A) entrada <produto> <qtd>? (a <preco>)?
  let m = rest.match(/^(.*?)(?:\s+(\d+))?(?:\s+a\s+(\d+[.,]?\d*))?$/i);
  let hit = tryParse(m, 1, 2, 3);
  if (hit) return hit;

  // B) entrada (de )?<qtd> (do|da|de)? <produto> (a <preco>)?
  m = rest.match(/^(?:de\s+)?(\d+)\s+(?:do|da|de)?\s*(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$/i);
  hit = tryParse(m, 2, 1, 3);
  if (hit) return hit;

  return null;
}

/* ========= Callable (sem CORS) ========= */
export const actCallV2 = onCall<ActCallInput, ActCallOutput>(
  { timeoutSeconds: 60, memory: "512MiB" },
  (req) => {
    try {
      const data = (req.data ?? {}) as Partial<ActCallInput>;
      const requestId = String(data.requestId ?? "");
      const tenantId  = String(data.tenantId  ?? "");
      const role      = String(data.role      ?? "");
      const text      = String(data.text      ?? "");

      if (!requestId || !tenantId || !role || !text) {
        logger.warn("invalid-argument", { requestId, tenantId, role, text });
        throw new HttpsError("invalid-argument", "Interpretação incompleta.");
      }

      logger.info("actCallV2 received", { requestId, tenantId, role, text });

      const entrada = parseEntrada(text);
      if (entrada) {
        const { produto, quantidade, preco } = entrada;
        let msg = `Proposta: entrada em "${produto}"`;
        if (quantidade !== undefined) msg += ` de ${quantidade} un.`;
        if (preco      !== undefined) msg += ` a ${preco.toFixed(2)}`;
        msg += `. Confirmar?`;

        return {
          requestId,
          ok: true,
          message: msg,
          intent: "entrada",
          parsed: { produto, quantidade, preco },
        };
      }

      return {
        requestId,
        ok: true,
        intent: "desconhecido",
        message:
          'Não entendi. Tente: "entrada coca-cola", "entrada coca-cola 10" ou "entrada coca-cola 10 a 5,50".',
      };
    } catch (err: any) {
      logger.error("actCallV2 error", { err });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "Falha interna.", String(err?.message ?? err));
    }
  }
);

/* ========= Chat opcional (Vertex) — também callable ========= */
type ChatInput  = { tenantId?: string; userId?: string; text?: string };
type ChatOutput = { reply: string };

// extrai texto do objeto do Gemini sem usar .text()
function extractGeminiText(resp: any): string {
  try {
    const parts = resp?.candidates?.[0]?.content?.parts ?? [];
    return (parts.map((p: any) => p?.text ?? "").join("") || "").trim();
  } catch { return ""; }
}

export const chatRespond = onCall<ChatInput, ChatOutput>(
  { timeoutSeconds: 60, memory: "512MiB" },
  async (req): Promise<ChatOutput> => {
    const text = String(req.data?.text ?? "").trim();
    if (!text) return { reply: "Ok." };

    // Fallback local rápido (orienta telas certas)
    if (/\b(entrada|dar entrada|estoque\+)\b/i.test(text)) {
      return { reply: 'Para lançar **entrada**, abra o produto e toque em **Registrar entrada**.' };
    }
    if (/\b(sa[ií]da|venda|baixar estoque)\b/i.test(text)) {
      return { reply: 'Para registrar **saída/venda**, use o botão **Vender** na tela Início.' };
    }

    if (process.env.ENABLE_VERTEX === "1") {
      try {
        // import dinâmico p/ não exigir o pacote se Vertex estiver desligado
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const { VertexAI } = require("@google-cloud/vertexai");
        const project  = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
        const location = process.env.VERTEX_LOCATION || "us-central1";
        const modelId  = process.env.VERTEX_MODEL || "gemini-1.5-flash-8b";

        const vertexAI = new VertexAI({ project, location });
        const model = vertexAI.getGenerativeModel({ model: modelId });
        const result = await model.generateContent({
          contents: [{ role: "user", parts: [{ text }] }],
        });

        const reply = extractGeminiText(result?.response) || "Ok.";
        return { reply };
      } catch (err) {
        logger.warn("vertex-fallback", { err: String(err) });
      }
    }

    return {
      reply:
        "Posso ajudar com consultas de estoque, itens em falta e sugestões. " +
        "Para **entrada** use a tela do produto; para **saída** use **Vender**.",
    };
  }
);
