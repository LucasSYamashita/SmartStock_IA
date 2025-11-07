import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import express from "express";
import cors from "cors";

admin.initializeApp();

const app = express();
app.use(cors({ origin: true })); // ✅ habilita CORS globalmente

/* ======== Funções utilitárias ======== */
function normalize(text: string): string {
    return text
        .toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .trim();
}

function classifyIntent(
    t: string
): "entrada" | "saida" | "consulta" | "sugestao" | "geral" {
    if (/\b(entrada|comprar|repor|adicionar)\b/i.test(t)) return "entrada";
    if (/\b(saida|venda|vender|baixar)\b/i.test(t)) return "saida";
    if (/\b(quanto|tem|estoque|saldo|quantidade)\b/i.test(t)) return "consulta";
    if (/\b(sugira|recomende|indique|baixo estoque|repor|sugestao|reposição)\b/i.test(t))
        return "sugestao";
    return "geral";
}

function parseMovimento(text: string) {
    const t = normalize(text);

    // entrada 10 coca a 8,50
    let m = t.match(/(entrada|repor|comprar)\s+(\d+)\s+(.+?)\s+a\s+(\d+[.,]?\d*)/);
    if (m)
        return {
            tipo: "entrada"
            as
            const,
            quantidade: +m[2],
            produto: m[3].trim(),
            preco: parseFloat(m[4].replace(",", ".")),
        };

    // entrada 10 coca
    m = t.match(/(entrada|repor|comprar)\s+(\d+)\s+(.+)/);
    if (m)
        return {
            tipo: "entrada"
            as
            const,
            quantidade: +m[2],
            produto: m[3].trim(),
        };

    // saida 3 coca
    m = t.match(/(saida|venda|vender|baixar)\s+(\d+)\s+(.+)/);
    if (m)
        return {
            tipo: "saida"
            as
            const,
            quantidade: +m[2],
            produto: m[3].trim(),
        };

    return null;
}

/* ======== Firestore ======== */
async function registrarMovimento(
    tenantId: string,
    userId: string,
    tipo: "entrada" | "saida",
    produtoNome: string,
    quantidade: number,
    preco ? : number
) {
    const db = admin.firestore();
    const nomeLower = produtoNome.toLowerCase();
    const colProd = db.collection("tenants").doc(tenantId).collection("produtos");
    const snap = await colProd.where("nomeLower", "==", nomeLower).limit(1).get();

    let ref: FirebaseFirestore.DocumentReference;
    let data: any;

    if (snap.empty) {
        ref = await colProd.add({
            nome: produtoNome,
            nomeLower,
            quantidade: tipo === "entrada" ? quantidade : 0,
            preco: preco ? ? 0,
            estoqueMinimo: 1,
            ativo: true,
            categoria: "",
            sku: "",
            createdBy: userId,
            updatedBy: userId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        data = { quantidade: 0, preco: preco ? ? 0 };
    } else {
        ref = snap.docs[0].ref;
        data = snap.docs[0].data();
    }

    const atual = data.quantidade ? ? 0;
    const delta = tipo === "entrada" ? quantidade : -quantidade;
    const novoEstoque = Math.max(atual + delta, 0);

    await ref.update({
        quantidade: novoEstoque,
        preco: preco ? ? data.preco ? ? 0,
        updatedBy: userId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await db.collection("tenants").doc(tenantId).collection("movimentos").add({
        tipo,
        produtoId: ref.id,
        produtoNome,
        quantidade,
        preco: preco ? ? data.preco ? ? 0,
        valorTotal: (preco ? ? data.preco ? ? 0) * quantidade,
        usuarioId: userId,
        tenantId,
        origem: "chat",
        motivo: "chatbot",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return novoEstoque;
}

/* ======== Sugestão ======== */
async function gerarSugestaoLocal(tenantId: string): Promise < string > {
    const db = admin.firestore();
    const snap = await db
        .collection("tenants")
        .doc(tenantId)
        .collection("produtos")
        .where("quantidade", "<=", 3)
        .limit(5)
        .get();

    if (snap.empty) return "Nenhum produto com baixo estoque.";
    const lista = snap.docs.map((d) => `${d.data().nome} (${d.data().quantidade})`);
    return `Sugestão de reposição: ${lista.join(", ")}.`;
}

/* ======== Rota principal ======== */
app.post("/", async(req, res) => {
    try {
        const { tenantId, userId, text } = req.body;
        if (!tenantId || !userId || !text) {
            res.json({ ok: false, intent: "erro", message: "Parâmetros ausentes." });
            return;
        }

        const t = normalize(text);
        const intent = classifyIntent(t);

        if (intent === "entrada" || intent === "saida") {
            const parsed = parseMovimento(t);
            if (parsed ? .produto && parsed ? .quantidade) {
                const novoEstoque = await registrarMovimento(
                    tenantId,
                    userId,
                    intent,
                    parsed.produto,
                    parsed.quantidade,
                    parsed.preco
                );

                const msg =
                    intent === "entrada" ?
                    `✅ Entrada registrada: +${parsed.quantidade}x ${parsed.produto}. Agora há ${novoEstoque} em estoque.` :
                    `✅ Saída registrada: -${parsed.quantidade}x ${parsed.produto}. Agora há ${novoEstoque} em estoque.`;

                res.json({ ok: true, intent, message: msg });
                return;
            }
        }

        if (intent === "consulta") {
            const nome = t
                .replace(/(quanto|tem|estoque|saldo|quantidade)/g, "")
                .trim();
            const snap = await admin
                .firestore()
                .collection("tenants")
                .doc(tenantId)
                .collection("produtos")
                .where("nomeLower", "==", nome.toLowerCase())
                .limit(1)
                .get();

            if (snap.empty) {
                res.json({
                    ok: true,
                    intent,
                    message: `Produto "${nome}" não encontrado.`,
                });
                return;
            }

            const data = snap.docs[0].data();
            res.json({
                ok: true,
                intent,
                message: `📦 Há ${data.quantidade} unidade(s) de ${data.nome}.`,
            });
            return;
        }

        if (intent === "sugestao") {
            const msg = await gerarSugestaoLocal(tenantId);
            res.json({ ok: true, intent, message: msg });
            return;
        }

        res.json({
            ok: true,
            intent,
            message: "Posso ajudar com **entrada**, **saída**, **consulta** e **sugestão**. Ex: 'entrada 10 coca a 8,50', 'venda 2 coca', 'quanto tem de arroz', 'o que repor'.",
        });
    } catch (err: any) {
        console.error("❌ Erro interno:", err);
        res.status(500).json({
            ok: false,
            intent: "erro",
            message: err.message,
        });
    }
});

/* ======== Export ======== */
export const chatRespond = functions
    .region("southamerica-east1")
    .https.onRequest(app);