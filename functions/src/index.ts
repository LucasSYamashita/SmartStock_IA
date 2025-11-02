// functions/src/index.ts
import * as admin from "firebase-admin";

// v2 APIs
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";

admin.initializeApp();

// defina a região e limites globais (pode ajustar)
setGlobalOptions({
  region: "southamerica-east1",
  maxInstances: 10,
});

type Msg = { role: "user" | "assistant"; content: string };

const ok = (data: any) => ({ ok: true, ...data });
const fail = (code: Parameters<typeof HttpsError>[0], message: string, data: any = {}) =>
  new HttpsError(code, message, data);

// [id:req_xxx] do último texto do usuário
function parseRequestId(messages: Msg[]): string | null {
  const lastUser = [...messages].reverse().find((m) => m.role === "user");
  if (!lastUser) return null;
  const m = /\[id:(.+?)\]/.exec(lastUser.content);
  return m?.[1] ?? null;
}

// extrai estado (produto, quantidade, preco, pular, confirmar) varrendo TUDO
function extractState(messages: Msg[]) {
  const lowAll = messages.map((m) => ({ ...m, content: m.content.toLowerCase() }));

  // preço
  let preco: number | null = null;
  for (const m of [...lowAll].reverse()) {
    const p1 = m.content.match(/\ba\s+(\d+(?:[.,]\d+)?)/);
    const p2 = m.content.match(/\bpor\s+(\d+(?:[.,]\d+)?)/);
    const p3 = m.content.match(/r\$\s*(\d+(?:[.,]\d+)?)/);
    const raw = (p1?.[1] ?? p2?.[1] ?? p3?.[1])?.replace(",", ".");
    if (raw && !Number.isNaN(parseFloat(raw))) { preco = parseFloat(raw); break; }
  }

  // quantidade
  let quantidade: number | null = null;
  for (const m of [...lowAll].reverse()) {
    const q = m.content.match(/(^|\s)(\d+)(\s|$)/);
    if (q) { const n = parseInt(q[2], 10); if (n > 0) { quantidade = n; break; } }
  }

  // produto
  let produto: string | null = null;
  for (const m of [...lowAll].reverse()) {
    const pA = m.content.match(/entrada\s+(?:de\s+)?([\p{L}\- ]+)/u);
    const pB = m.content.match(/\bem\s+([\p{L}\- ]+)/u);
    const pC = m.content.match(/\bde\s+([\p{L}\- ]+)/u);
    const cand = (pA?.[1] ?? pB?.[1] ?? pC?.[1])?.trim();
    if (cand) { produto = cand.replace(/\s+$/g, "").replace(/\s+/g, " "); break; }
  }

  const skipPreco = lowAll.some((m) => /\bpular\b/.test(m.content));
  const confirmar = lowAll.some((m) => /\bconfirma(r|do)?\b|\bok\b/.test(m.content));

  return { produto, quantidade, preco, skipPreco, confirmar };
}

export const actCall = onCall(async (request) => {
  try {
    const data = request.data as {
      tenantId?: string;
      role?: string;
      messages?: Msg[];
      dryRun?: boolean;
    };

    const tenantId = String(data?.tenantId || "");
    const role = String(data?.role || "viewer"); // apenas informativo
    const messages = (data?.messages || []) as Msg[];
    const dryRun = Boolean(data?.dryRun);

    if (!tenantId) throw fail("invalid-argument", "missing-tenantId");
    if (!messages?.length) throw fail("invalid-argument", "missing-messages");
    if (!request.auth?.uid) throw fail("unauthenticated", "auth-required");

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

    let prodId: string;
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
    } else {
      const doc = prodSnap.docs[0];
      prodId = doc.id;
      prodNome = (doc.get("nome") as string) || prodNome;
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

    const assistant_text =
      (preco != null)
        ? `✅ Entrada de ${quantidade} un. em "${prodNome}" registrada (preço ${preco}).`
        : `✅ Entrada de ${quantidade} un. em "${prodNome}" registrada.`;

    return ok({
      assistant_text,
      result: { produto: prodNome, quantidade, preco, requestId },
    });
  } catch (err: any) {
    if (err instanceof HttpsError) throw err;
    console.error(err);
    throw new HttpsError("internal", "Falha interna.", { detail: String(err?.message ?? err) });
  }
});
