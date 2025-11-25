import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { VertexAI } from "@google-cloud/vertexai";

admin.initializeApp();

/* ============ Vertex AI (Gemini) ============ */

const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.GCLOUD_PROJECT_ID ||
  process.env.PROJECT_ID ||
  "smartstock-ae7ad";

const LOCATION = "us-central1";

// 🔹 ID do modelo no Vertex (precisa bater com o mostrado no console do GCP)
const MODEL_ID = "gemini-2.5-flash-lite";

const vertexAI = new VertexAI({
  project: PROJECT_ID,
  location: LOCATION,
});

const stockModel = vertexAI.getGenerativeModel({
  model: MODEL_ID,
});

type ParsedOp = {
  tipo: "entrada" | "saida";
  quantidade: number;
  produtoNome: string;
  motivo?: string | null;
  preco?: number | null;
};

type ParsedVertexResult = {
  operations: ParsedOp[];
  answer: string | null;
};

/**
 * IA: interpreta a frase e devolve operações + resposta de negócio.
 */
async function parseWithVertex(
  text: string,
  locale = "pt-BR",
): Promise<ParsedVertexResult> {
  const prompt = `
Você é um assistente de controle de estoque e negócios para pequenos e médios empreendedores.
Sua tarefa é LER a frase do usuário em linguagem natural e devolver APENAS um JSON com:

{
  "operations": [...],
  "answer": "..."
}

REGRAS IMPORTANTES:
- Responda SOMENTE com um JSON válido, sem texto fora do JSON.
- Não use markdown, não use comentários, não explique nada fora do JSON.
- "operations" DEVE ser sempre um array (lista).
- "answer" DEVE ser sempre uma string (pode ser "" quando não tiver nada para falar).

REGRAS PARA "operations":
- Cada item de "operations" representa uma movimentação de estoque.
- Cada operação deve ter:
  - "tipo": "entrada" ou "saida"
  - "quantidade": número inteiro > 0
  - "produtoNome": string com o nome do produto (como o usuário fala)
  - "preco": número (opcional, unitário; null se não mencionado)
  - "motivo": string opcional (por ex.: "venda", "reabasteci a geladeira")

MAPEAMENTO DE VERBOS:
- Trate como **ENTRADA** frases com verbos como:
  "entrada", "entrei", "entrou", "adiciona", "adicionar", "somar", "somar ao estoque",
  "repor", "reabasteci", "reabastecer", "comprar para o estoque", "comprei para o estoque".
- Trate como **SAÍDA** frases com verbos como:
  "vendi", "venda", "vender", "saída", "saida", "baixar", "baixei", "baixar do estoque",
  "retirei", "retirar", "usei", "consumi", "saiu do estoque".

REGRAS PARA "answer":
- Use "answer" para responder dúvidas do usuário sobre negócio, marcas, sugestões, desempenho de produtos, etc.
- Escreva SEMPRE em português do Brasil, de forma objetiva e prática.
- Se a frase do usuário NÃO pedir opinião ou explicação, deixe "answer" como "" (string vazia).

EXEMPLOS:

1) Frase: "faz uma entrada de 7 coca-cola lata a 4,25 porque reabasteci a geladeira"

JSON:
{
  "operations": [
    {
      "tipo": "entrada",
      "quantidade": 7,
      "produtoNome": "coca-cola lata",
      "preco": 4.25,
      "motivo": "reabasteci a geladeira"
    }
  ],
  "answer": ""
}

2) Frase: "ontem vendi 3 coca lata a 5 reais e 2 fanta uva a 4,50"

JSON:
{
  "operations": [
    {
      "tipo": "saida",
      "quantidade": 3,
      "produtoNome": "coca lata",
      "preco": 5.0,
      "motivo": "venda"
    },
    {
      "tipo": "saida",
      "quantidade": 2,
      "produtoNome": "fanta uva",
      "preco": 4.5,
      "motivo": "venda"
    }
  ],
  "answer": ""
}

3) Frase: "vendi 3 coca lata"

JSON:
{
  "operations": [
    {
      "tipo": "saida",
      "quantidade": 3,
      "produtoNome": "coca lata",
      "preco": null,
      "motivo": "venda"
    }
  ],
  "answer": ""
}

4) Frase: "qual a melhor marca de refrigerante para um mercadinho de bairro?"

JSON:
{
  "operations": [],
  "answer": "Explique de forma objetiva os pontos principais a considerar (preferência dos clientes da região, preço, giro de estoque, possibilidade de negociação com fornecedor, marcas líderes e marcas regionais, etc.). Não invente dados de vendas específicos, foque em orientação prática."
}

5) Frase: "o que você sugere de produto de limpeza para aumentar a saída na minha mercearia?"

JSON:
{
  "operations": [],
  "answer": "Sugira linhas de produtos de limpeza com boa saída em mercados de bairro (detergentes, desinfetantes, sabão em pó, multiuso, etc.), com foco em equilíbrio entre preço e qualidade. Fale de maneira prática para um pequeno empreendedor."
}

6) Frase: "reabasteci 10 água sem gás 500ml, está bom esse nível de estoque?"

JSON:
{
  "operations": [
    {
      "tipo": "entrada",
      "quantidade": 10,
      "produtoNome": "água sem gás 500ml",
      "preco": null,
      "motivo": "reabastecimento"
    }
  ],
  "answer": "Dê uma orientação geral sobre como avaliar se 10 unidades é um bom nível (giro médio, sazonalidade, espaço físico, capital parado, etc.)."
}

Frase do usuário (locale=${locale}):
"${text}"
`;

  try {
    const result = await stockModel.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: prompt }],
        },
      ],
    });

    let raw =
      result.response.candidates?.[0]?.content?.parts?.[0]?.text || "{}";

    console.log("RAW GEMINI:", raw);

    // 🔧 Remove ```json ... ``` se o modelo devolver em code block
    let cleaned = raw.trim();
    if (cleaned.startsWith("```")) {
      const firstNewline = cleaned.indexOf("\n");
      if (firstNewline !== -1) {
        cleaned = cleaned.substring(firstNewline + 1);
      }
      const lastFence = cleaned.lastIndexOf("```");
      if (lastFence !== -1) {
        cleaned = cleaned.substring(0, lastFence);
      }
      cleaned = cleaned.trim();
    }

    let json: any;
    try {
      json = JSON.parse(cleaned);
    } catch (e) {
      console.error("⚠️ Vertex retornou JSON inválido:", cleaned);
      return { operations: [], answer: null };
    }

    const opsRaw = Array.isArray(json.operations) ? json.operations : [];
    const parsedOps: ParsedOp[] = [];

    for (const op of opsRaw) {
      if (!op) continue;
      const tipo =
        op.tipo === "entrada" || op.tipo === "saida" ? op.tipo : undefined;
      const qtd = Number(op.quantidade || 0);
      const nome = String(op.produtoNome || "").trim();
      const preco =
        op.preco === null || op.preco === undefined
          ? null
          : Number(op.preco);
      const motivo =
        op.motivo === null || op.motivo === undefined
          ? null
          : String(op.motivo);

      if (!tipo || !nome || !Number.isFinite(qtd) || qtd <= 0) continue;

      parsedOps.push({
        tipo,
        quantidade: qtd,
        produtoNome: nome,
        preco: preco ?? null,
        motivo,
      });
    }

    const answerText =
      typeof json.answer === "string" && json.answer.trim().length > 0
        ? json.answer.trim()
        : null;

    return {
      operations: parsedOps,
      answer: answerText,
    };
  } catch (err) {
    console.error("❌ Erro ao chamar Vertex:", err);
    return { operations: [], answer: null };
  }
}

/* ============ Utils locais (fallback) ============ */

function normalize(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();
}

/**
 * Fallback simples só pra detectar consulta/sugestão quando IA não ajuda.
 */
function looksLikeConsulta(t: string): boolean {
  return /\b(quanto|tem|estoque|saldo)\b/i.test(t);
}

function looksLikeSugestao(t: string): boolean {
  return /\b(sugira|sugere|recomende|recomenda|indique|indica|baixo estoque|repor|comprar mais|melhor marca|melhores produtos|aumentar a saida|aumentar a saída|produto de limpeza)\b/i.test(
    t,
  );
}

function looksLikeBaixoEstoqueSugestao(t: string): boolean {
  return /\b(baixo estoque|repor|comprar mais)\b/i.test(t);
}

/**
 * Fallback de movimento para UMA operação simples (entrada/saida).
 * Usado só se a IA não conseguir extrair nada.
 *
 * IMPORTANTE: se detectar padrão de MAIS de um produto (" e 2 fanta..."),
 * não tenta adivinhar, retorna null pra evitar criar produto zoado.
 */
function parseMovimento(text: string) {
  const t = normalize(text);

  // se tem " e " depois de um número, provavelmente é multi-produto → deixa pra IA
  const multiProduto = /\d+[^0-9]*\se\s+\d+/.test(t);
  if (multiProduto) return null;

  let m;

  // ENTRADAS (entrada, reabasteci, comprei, repor...)
  m = t.match(
    /\b(entrada|entrei|entrou|adiciona|adicionar|somar|somar ao estoque|repor|reabasteci|reabastecer|comprar para o estoque|comprei para o estoque|comprar)\s+(?:de\s+)?(\d+)\s+(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$/i,
  );
  if (m) {
    return {
      tipo: "entrada" as const,
      quantidade: Number(m[2]),
      produto: m[3].trim(),
      preco: m[4] ? Number(m[4].replace(",", ".")) : null,
    };
  }

  // SAÍDAS (vendi, venda, vender, saida, retirei, baixei, usei, consumi...)
  m = t.match(
    /\b(saida|saída|venda|vender|vendi|vendemos|retirei|retirar|retiramos|baixar|baixei|baixamos|usei|usamos|consumi|consumimos|saiu do estoque)\s+(\d+)\s+(.+?)(?:\s+a\s+(\d+[.,]?\d*))?$/i,
  );
  if (m) {
    return {
      tipo: "saida" as const,
      quantidade: Number(m[2]),
      produto: m[3].trim(),
      preco: m[4] ? Number(m[4].replace(",", ".")) : null,
    };
  }

  return null;
}

/* ============ Helper: registrar movimento no Firestore ============ */
async function registrarMovimento(
  tenantId: string,
  userId: string,
  tipo: "entrada" | "saida",
  produtoNome: string,
  quantidade: number,
  preco?: number | null,
) {
  const db = admin.firestore();

  // normaliza nome do produto (igual ao app / Flutter)
  const nomeTrim = produtoNome.trim();
  const keySimple = nomeTrim.toLowerCase(); // ex.: "coca cola"
  const keyNorm = normalize(produtoNome);   // remove acentos etc.
  const keys = Array.from(new Set([keySimple, keyNorm])); // evita duplicata

  const colProd = db
    .collection("tenants")
    .doc(tenantId)
    .collection("produtos");

  let ref: FirebaseFirestore.DocumentReference;
  let data: any = {};

  // 1) tenta doc cujo ID é o nome normalizado
  const directRef = colProd.doc(keySimple);
  const directSnap = await directRef.get();

  if (directSnap.exists) {
    ref = directRef;
    data = directSnap.data() || {};
  } else {
    // 2) tenta achar por nomeLower (compat com versões antigas)
    let snap: FirebaseFirestore.QuerySnapshot<FirebaseFirestore.DocumentData>;
    if (keys.length === 1) {
      snap = await colProd.where("nomeLower", "==", keys[0]).limit(1).get();
    } else {
      snap = await colProd.where("nomeLower", "in", keys).limit(1).get();
    }

    if (!snap.empty) {
      // achou produto existente
      ref = snap.docs[0].ref;
      data = snap.docs[0].data() || {};
    } else {
      // 3) não existe → cria doc novo com ID = keySimple
      ref = directRef;
      data = {
        quantidade: 0,
        preco: preco ?? 0,
      };

      await ref.set({
        nome: nomeTrim,
        nomeLower: keySimple,
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
    }
  }

  const atual =
    typeof data.quantidade === "number" ? data.quantidade : 0;

  // preço base: o da operação, senão o do produto, senão 0
  const precoBase =
    typeof preco === "number" && !Number.isNaN(preco)
      ? preco
      : typeof data.preco === "number"
      ? data.preco
      : 0;

  const delta = tipo === "entrada" ? quantidade : -quantidade;
  const novoEstoque = Math.max(atual + delta, 0);
  const totalLinha = precoBase * quantidade;

  // atualiza produto
  await ref.update({
    quantidade: novoEstoque,
    preco: precoBase,
    updatedBy: userId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // registra movimento
  await db
    .collection("tenants")
    .doc(tenantId)
    .collection("movimentos")
    .add({
      tipo,
      produtoId: ref.id,
      produtoNome: nomeTrim,
      quantidade,
      preco: precoBase,
      valorTotal: totalLinha,
      usuarioId: userId,
      tenantId,
      origem: "chat",
      motivo: tipo === "entrada" ? "Entrada via chat" : "Saída via chat",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  return novoEstoque;
}


/* ============ SUGESTÃO LOCAL (baixo estoque) ============ */
async function gerarSugestaoLocal(tenantId: string) {
  const snap = await admin
    .firestore()
    .collection("tenants")
    .doc(tenantId)
    .collection("produtos")
    .where("quantidade", "<=", 3)
    .limit(6)
    .get();

  if (snap.empty) return "📦 Nenhum item com baixo estoque.";

  const lista = snap.docs.map(
    (d) => `${d.data().nome} (qtd ${d.data().quantidade})`,
  );

  return `🔎 Itens com baixo estoque: ${lista.join(", ")}`;
}

/* =============================================
 *  🚀 chatRespond — onCall (IA + fallback)
 * ============================================= */
export const chatRespond = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    try {
      const text = String(data?.text ?? "").trim();
      const tenantId = data?.tenantId ?? "";
      const userId = data?.userId ?? "";
      const enableVertex = data?.enableVertex !== false; // padrão: true

      if (!text || !tenantId || !userId) {
        return {
          ok: false,
          intent: "erro",
          message: "Informe tenantId, userId e texto.",
        };
      }

      const tNorm = normalize(text);

      let operations: ParsedOp[] = [];
      let aiAnswer: string | null = null;

      // 1) Tenta IA primeiro
      if (enableVertex) {
        const ai = await parseWithVertex(text, "pt-BR");
        operations = ai.operations;
        aiAnswer = ai.answer;
        if (operations.length) {
          console.log("🤖 Vertex operations:", JSON.stringify(operations));
        }
        if (aiAnswer) {
          console.log("🤖 Vertex answer:", aiAnswer);
        }
      }

      // 2) Se não houve operação pela IA, tenta regex simples
      if (!operations.length) {
        const parsed = parseMovimento(text);
        if (parsed) {
          operations.push({
            tipo: parsed.tipo,
            quantidade: parsed.quantidade ?? 1,
            produtoNome: parsed.produto,
            preco: parsed.preco ?? null,
            motivo: null,
          });
        }
      }

      // 2.5) Sanitiza operações vindas da IA (casos em que ela junta nome + preço + motivo)
      operations = operations.map((op) => {
        let { produtoNome, preco, motivo } = op;
        const m = produtoNome.match(/^(.+?)\s+a\s+(\d+[.,]?\d*)(.*)$/i);
        if (m) {
          const nomeLimpo = m[1].trim();
          const precoStr = m[2];
          const resto = m[3].trim();

          if (preco == null) {
            preco = Number(precoStr.replace(",", "."));
          }
          if (!motivo && resto) {
            motivo = resto.replace(/^porque\s+/i, "").trim();
          }

          return {
            ...op,
            produtoNome: nomeLimpo,
            preco,
            motivo,
          };
        }
        return op;
      });

      // 3) Se temos operações, registra movimentos
      if (operations.length > 0) {
        const mensagens: string[] = [];

        for (const op of operations) {
          const novoEstoque = await registrarMovimento(
            tenantId,
            userId,
            op.tipo,
            op.produtoNome,
            op.quantidade,
            op.preco,
          );

          const precoTxt =
            op.preco != null && !Number.isNaN(op.preco)
              ? ` a R$${op.preco.toFixed(2)}`
              : "";

          if (op.tipo === "entrada") {
            mensagens.push(
              `✅ Entrada: +${op.quantidade}x ${op.produtoNome}${precoTxt}. Estoque: ${novoEstoque}.`,
            );
          } else {
            mensagens.push(
              `✅ Saída: -${op.quantidade}x ${op.produtoNome}${precoTxt}. Estoque atual: ${novoEstoque}.`,
            );
          }
        }

        let finalMessage = mensagens.join("\n");
        if (aiAnswer) {
          finalMessage += `\n\n💡 ${aiAnswer}`;
        }

        return {
          ok: true,
          intent: "movimento",
          message: finalMessage,
        };
      }

      // 4) Perguntas de sugestão / negócio (com ou sem IA)
      if (looksLikeSugestao(tNorm)) {
        // se a IA respondeu, usa a resposta dela
        if (aiAnswer) {
          return {
            ok: true,
            intent: "analise",
            message: aiAnswer,
          };
        }

        // se a pergunta é de "baixo estoque / repor / comprar mais", usa a sugestão local
        if (looksLikeBaixoEstoqueSugestao(tNorm)) {
          const msg = await gerarSugestaoLocal(tenantId);
          return {
            ok: true,
            intent: "sugestao",
            message: msg,
          };
        }

        // fallback genérico de negócio quando a IA não está disponível
        return {
          ok: true,
          intent: "analise",
          message:
            "No momento não consegui usar a IA para uma análise detalhada, " +
            "mas, em geral, vale observar: perfil dos seus clientes, preço final ao consumidor, " +
            "margem de lucro, qualidade percebida, giro de vendas e condições de negociação com o fornecedor. " +
            "Priorize marcas que tenham boa saída na sua região, ofereçam entrega confiável e permitam um equilíbrio entre preço competitivo e lucro.",
        };
      }

      // 5) Fallback de consulta de estoque
      if (looksLikeConsulta(tNorm)) {
        const nome = tNorm
          .replace(/(quanto|tem|estoque|saldo|de|do|da|dos|das)/g, "")
          .trim();

        if (!nome) {
          return {
            ok: true,
            intent: "consulta",
            message:
              'Para consultar, você pode dizer: "quanto tem de coca lata?"',
          };
        }

        const snap = await admin
          .firestore()
          .collection("tenants")
          .doc(tenantId)
          .collection("produtos")
          .where("nomeLower", "==", nome.toLowerCase())
          .limit(1)
          .get();

        if (snap.empty)
          return {
            ok: true,
            intent: "consulta",
            message: `Produto "${nome}" não encontrado.`,
          };

        const d = snap.docs[0].data();
        return {
          ok: true,
          intent: "consulta",
          message: `📦 ${d.nome}: ${d.quantidade} unidade(s) em estoque.`,
        };
      }

      // 6) Outras perguntas em que a IA respondeu algo
      if (aiAnswer) {
        return {
          ok: true,
          intent: "analise",
          message: aiAnswer,
        };
      }

      // 7) Mensagem genérica de ajuda
      return {
        ok: true,
        intent: "geral",
        message:
          "Posso ajudar com **entrada**, **saída**, **consulta** e **sugestões de negócio**.\n" +
          "Exemplos:\n" +
          "- 'faz uma entrada de 7 coca-cola lata a 4,25 porque reabasteci a geladeira'\n" +
          "- 'vendi 3 coca lata a 5 reais'\n" +
          "- 'quanto tem de arroz?'\n" +
          "- 'qual a melhor marca de refrigerante para um mercadinho de bairro?'\n" +
          "- 'o que você sugere de produto de limpeza para aumentar a saída?'",
      };
    } catch (err: any) {
      console.error("❌ Erro interno:", err);
      return {
        ok: false,
        intent: "erro",
        message: "Erro interno: " + String(err?.message),
      };
    }
  });
