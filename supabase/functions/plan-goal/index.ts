import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface QuestionsRequest {
  goal_description: string;
}

interface PlanRequest {
  goal_description: string;
  answers: Array<{ question: string; answer: string }>;
}

const MODEL = "claude-sonnet-4-5";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!anthropicKey) {
    return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch (e) {
    return new Response(JSON.stringify({ error: "Invalid JSON: " + String(e) }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const hasAnswers =
    Array.isArray((body as PlanRequest).answers) &&
    (body as PlanRequest).answers.length > 0;

  try {
    if (!hasAnswers) {
      const { goal_description } = body as QuestionsRequest;
      console.log("Phase 1, model:", MODEL, "goal:", goal_description?.slice(0, 60));

      const text = await callClaude(anthropicKey, [
        {
          role: "user",
          content: `You are a personal goal coach. A user wants to achieve:\n"${goal_description}"\n\nGenerate exactly 4 specific clarifying questions about their current baseline, timeline, constraints, and motivation. Respond ONLY with valid JSON (no markdown):\n{"questions":["q1","q2","q3","q4"]}`,
        },
      ]);

      console.log("Claude response (first 150):", text.slice(0, 150));
      return jsonResponse(JSON.parse(cleanJson(text)));
    } else {
      const { goal_description, answers } = body as PlanRequest;
      console.log("Phase 2, model:", MODEL, "answers:", answers.length);

      const answersText = answers
        .map((a) => `Q: ${a.question}\nA: ${a.answer}`)
        .join("\n\n");
      const today = new Date().toISOString().split("T")[0];

      const text = await callClaude(anthropicKey, [
        {
          role: "user",
          content: `You are a personal goal coach. Create a structured action plan.\n\nGoal: ${goal_description}\nToday: ${today}\n\nUser answers:\n${answersText}\n\nCreate a realistic ladder of 4-6 activities. Types: habit (recurring), goal (measurable, needs goal_target number), challenge (photo-verified), task (one-time).\n\nRespond ONLY with valid JSON (no markdown):\n{"title":"Plan title","summary":"2-3 sentence summary","activities":[{"step_number":1,"title":"title","description":"what and why","type":"habit","frequency":"daily","condition":null,"goal_target":null,"deadline_days":30,"rationale":"one sentence"}]}`,
        },
      ]);

      console.log("Claude response (first 150):", text.slice(0, 150));
      return jsonResponse(JSON.parse(cleanJson(text)));
    }
  } catch (error) {
    console.error("plan-goal error:", String(error));
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

async function callClaude(
  apiKey: string,
  messages: Array<{ role: string; content: string }>
): Promise<string> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({ model: MODEL, max_tokens: 2048, messages }),
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`Anthropic ${res.status}: ${errBody}`);
  }
  const data = await res.json();
  return data.content?.[0]?.text ?? "";
}

function cleanJson(text: string): string {
  return text.replace(/```json\s*/gi, "").replace(/```/g, "").trim();
}

function jsonResponse(data: unknown): Response {
  return new Response(JSON.stringify(data), {
    headers: { "Content-Type": "application/json", "Connection": "keep-alive" },
  });
}
