import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import cors from "cors";

admin.initializeApp();
const corsHandler = cors({ origin: true });

/* ============ Utils ============ */
function normalize(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();
}

function classifyIntent(t: string): string {
  if (/\b(entrada|comprar|repor|adicionar)\b/i.test(t)) return "entrada";
  if (/\b(saida|venda|vender|baixar)\b/i.test(t)) return "saida";
  if (/\b(quanto|tem|estoque|saldo)\b/i.test(t)) return "consulta";
  if (/\b(sugira|recomende|indique|baixo estoque|repor|comprar mais)\b/i.test(t))
    return "sugestao";
  return "geral";
}

function parseMovimento(text: string) {
  const t = normalize(text);
  let m;

  // entrada 10 coca a 8,50
  m = t.match(/(entrada|repor|comprar)\s+(\d+)\s+(.+?)\s+a\s+(\d+[.,]?\d*)/);
  if (m)
    return {
      tipo: "entrada",
      quantidade: +m[2],
      produto: m[3].trim(),
      preco: parseFloat(m[4].replace(",", ".")),
    };

  // entrada 10 coca
  m = t.match(/(entrada|repor|comprar)\s+(\d+)\s+(.+)/);
  if (m)
    return {
      tipo: "entrada",
      quantidade: +m[2],
      produto: m[3].trim(),
    };

  // saida 3 coca
  m = t.match(/(saida|venda|vender|baixar)\s+(\d+)\s+(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$/);
  if (m)
    return {
      tipo: "saida",
      quantidade: +m[2],
      produto: m[3].trim(),
      preco: m[4] ? parseFloat(m[4].replace(",", ".")) : undefined,
    };

  return null;
}

/* ============ Função auxiliar de estoque ============ */
async function registrarMovimento(
  tenantId: string,
  userId: string,
  tipo: "entrada" | "saida",
  produtoNome: string,
  quantidade: number,
  preco?: number
) {
  const db = admin.firestore();
  const nomeLower = produtoNome.toLowerCase();

  const colProd = db.collection("tenants").doc(tenantId).collection("produtos");
  const snap = await colProd.where("nomeLower", "==", nomeLower).limit(1).get();

  let ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  let data: any;

  if (snap.empty) {
    ref = await colProd.add({
      nome: produtoNome,
      nomeLower,
      quantidade: tipo === "entrada" ? quantidade : 0,
      preco: preco ?? 0,
      estoqueMinimo: 1,
      ativo: true,
      categoria: "",
      sku: "",
      createdBy: userId,
      updatedBy: userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    data = { quantidade: 0, preco: preco ?? 0 };
  } else {
    ref = snap.docs[0].ref;
    data = snap.docs[0].data();
  }

  const atual = data.quantidade ?? 0;
  const delta = tipo === "entrada" ? quantidade : -quantidade;
  const novoEstoque = Math.max(atual + delta, 0);

  await ref.update({
    quantidade: novoEstoque,
    preco: preco ?? data.preco ?? 0,
    updatedBy: userId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 🔧 Ajuste: garantir gravação de movimento com preço e valor total
  await db
    .collection("tenants")
    .doc(tenantId)
    .collection("movimentos")
    .add({
      tipo,
      produtoId: ref.id,
      produtoNome: produtoNome,
      quantidade,
      preco: preco ?? data.preco ?? 0,
      valorTotal: (preco ?? data.preco ?? 0) * quantidade,
      usuarioId: userId,
      tenantId,
      origem: "chat",
      motivo: tipo === "entrada" ? "Entrada via chat" : "Saída via chat",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  return novoEstoque;
}

/* ============ SUGESTÃO LOCAL ============ */
async function gerarSugestaoLocal(tenantId: string): Promise<string> {
  const db = admin.firestore();
  const snap = await db
    .collection("tenants")
    .doc(tenantId)
    .collection("produtos")
    .where("quantidade", "<=", 3)
    .limit(5)
    .get();

  if (snap.empty)
    return "📦 Nenhum item com baixo estoque.";

  const lista = snap.docs.map(
    (d) => `${d.data().nome} (qtd ${d.data().quantidade})`
  );
  return `🔎 Itens com baixo estoque: ${lista.join(", ")}.`;
}

/* ============ ENDPOINT PRINCIPAL ============ */
export const chatRespond = functions
  .region("southamerica-east1")
  .https.onRequest((req, res) => {
    corsHandler(req, res, async () => {
      try {
        const text = String(req.body?.text ?? "").trim();
        const tenantId = req.body?.tenantId ?? "";
        const userId = req.body?.userId ?? "";

        if (!text || !tenantId || !userId) {
          return res.status(400).json({
            ok: false,
            intent: "erro",
            message: "Parâmetros ausentes: tenantId, userId ou texto.",
          });
        }

        const t = normalize(text);
        const intent = classifyIntent(t);

        // ===== ENTRADA / SAÍDA =====
        if (intent === "entrada" || intent === "saida") {
          const parsed = parseMovimento(t);
          if (parsed?.produto && tenantId && userId) {
           const novoEstoque = await registrarMovimento(
  tenantId,
  userId,
  parsed.tipo as "entrada" | "saida",
  parsed.produto,
  parsed.quantidade ?? 1,
  parsed.preco
);


            return res.json({
              ok: true,
              intent: parsed.tipo,
              message:
                parsed.tipo === "entrada"
                  ? `✅ Entrada registrada: +${parsed.quantidade}x ${parsed.produto}. Novo estoque: ${novoEstoque}.`
                  : `✅ Saída registrada: -${parsed.quantidade}x ${parsed.produto}. Estoque atual: ${novoEstoque}.`,
            });
          }
          return res.json({
            ok: false,
            intent,
            message: "Não encontrei produto ou tenant.",
          });
        }

        // ===== CONSULTA =====
        if (intent === "consulta" && tenantId) {
          const nome = t.replace(/(quanto|tem|estoque|saldo|de)/g, "").trim();
          const snap = await admin
            .firestore()
            .collection("tenants")
            .doc(tenantId)
            .collection("produtos")
            .where("nomeLower", "==", nome.toLowerCase())
            .limit(1)
            .get();

          if (snap.empty)
            return res.json({
              ok: true,
              intent,
              message: `Produto "${nome}" não encontrado.`,
            });

          const data = snap.docs[0].data();
          return res.json({
            ok: true,
            intent,
            message: `📦 ${data.nome}: ${data.quantidade} unidade(s) em estoque.`,
          });
        }

        // ===== SUGESTÃO =====
        if (intent === "sugestao") {
          const msg = await gerarSugestaoLocal(tenantId);
          return res.json({ ok: true, intent, message: msg });
        }

        // ===== GERAL =====
        return res.json({
          ok: true,
          intent: "geral",
          message:
            "Posso ajudar com **entrada**, **saída**, **consulta** e **sugestão**. Ex: 'entrada 10 coca a 8,50', 'venda 3 coca', 'o que repor?'.",
        });
      } catch (err: any) {
        console.error("❌ Erro interno:", err);
        res.status(500).json({
          ok: false,
          intent: "erro",
          message: "Erro interno no servidor: " + String(err?.message),
        });
      }
    });
  });
