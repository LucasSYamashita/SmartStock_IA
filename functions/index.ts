import * as functions from "firebase-functions";

// Node 18+ já tem fetch global
const OPENAI_API_KEY = functions.config().openai.key; // setar com: firebase functions:config:set openai.key="sk-..."

export const parseStockCommand = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Faça login.");
  }
  const text = (data?.text ?? "").toString().trim();
  const locale = (data?.locale ?? "pt-BR").toString();

  if (!text) {
    throw new functions.https.HttpsError("invalid-argument", "Campo 'text' é obrigatório.");
  }
  if (!OPENAI_API_KEY) {
    throw new functions.https.HttpsError("failed-precondition", "OpenAI key não configurada.");
  }

  const systemPrompt = `
Você é um parser de comandos de estoque. Saída deve ser JSON válido, SEM texto extra.

Objetivo: Dado um texto em ${locale}, detectar zero ou mais operações de estoque.
Cada operação tem:
- tipo: "entrada" | "saida"
- quantidade: inteiro > 0
- produtoNome: string
- motivo: string opcional (ex: "venda", "compra", "ajuste")

Regras:
- Aceite linguagem natural (plural, vírgulas, "mais", "e", etc.).
- Se o texto menciona múltiplos itens, extraia todos.
- Ignore cumprimentos/ruído que não sejam operações.
- Nunca invente quantidades. Se faltar quantidade, não gere operação.
- Responda SOMENTE JSON no formato:
{
  "operations": [
    {"tipo":"entrada","quantidade":3,"produtoNome":"Parafuso 10mm","motivo":"compra"},
    ...
  ]
}
Se não houver operação, responda {"operations": []}.
`.trim();

  const body = {
    model: "gpt-4o-mini",
    temperature: 0,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: text }
    ]
  };

  const resp = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!resp.ok) {
    const msg = await resp.text();
    throw new functions.https.HttpsError("internal", `OpenAI falhou: ${resp.status} ${msg}`);
  }

  const json = await resp.json();
  const content = json?.choices?.[0]?.message?.content ?? "{}";

  let parsed: any;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new functions.https.HttpsError("internal", "Resposta não-JSON da IA.");
  }

  // Normalização/validação leve
  const ops = Array.isArray(parsed?.operations) ? parsed.operations : [];
  const clean = ops
    .filter((o: any) =>
      (o?.tipo === "entrada" || o?.tipo === "saida") &&
      Number.isInteger(o?.quantidade) && o.quantidade > 0 &&
      typeof o?.produtoNome === "string" && o.produtoNome.trim().length > 0
    )
    .map((o: any) => ({
      tipo: o.tipo,
      quantidade: o.quantidade,
      produtoNome: o.produtoNome.trim(),
      motivo: typeof o.motivo === "string" ? o.motivo.trim() : undefined,
    }));

  return { operations: clean };
});
