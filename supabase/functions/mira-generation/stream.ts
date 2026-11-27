export async function readCompletion(
  response: Response,
  onText?: (delta: string) => Promise<void>,
): Promise<unknown> {
  if (!response.body) throw Error("transient_provider_error");
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  let content = "";
  let finished = false;
  const eventData: string[] = [];
  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      buffer += chunk.value;
      if (buffer.length > 1_000_000) throw Error("provider_output_too_large");
      let end: number;
      while ((end = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, end).replace(/\r$/, "");
        buffer = buffer.slice(end + 1);
        if (line.startsWith("data:")) eventData.push(line.slice(5).trimStart());
        if (line || !eventData.length) continue;
        const data = eventData.join("\n");
        eventData.length = 0;
        if (data === "[DONE]") {
          if (!finished) throw Error("transient_provider_error");
          return JSON.parse(content);
        }
        const event = JSON.parse(data);
        if (event.error) throw Error("transient_provider_error");
        const choice = event.choices?.[0];
        if (!choice) continue;
        if (choice.delta?.refusal) throw Error("provider_refused");
        if (typeof choice.delta?.content === "string") {
          content += choice.delta.content;
          if (content.length > 1_000_000) {
            throw Error("provider_output_too_large");
          }
          await onText?.(choice.delta.content);
        }
        if (choice.finish_reason === "stop") finished = true;
        else if (choice.finish_reason) {
          throw Error("incomplete_provider_output");
        }
      }
    }
    throw Error("transient_provider_error");
  } catch (error) {
    if (error instanceof TypeError) throw Error("transient_provider_error");
    throw error;
  } finally {
    await reader.cancel().catch(() => {});
  }
}

export function observeObjectFields(
  onField: (key: string, value: unknown) => void,
): (delta: string) => void {
  let text = "";
  let depth = 0;
  let start = 0;
  let inString = false;
  let escaped = false;
  return (delta) => {
    const previousEnd = text.length;
    text += delta;
    for (let i = previousEnd; i < text.length; i++) {
      const char = text[i];
      if (inString) {
        if (escaped) escaped = false;
        else if (char === "\\") escaped = true;
        else if (char === '"') inString = false;
        continue;
      }
      if (char === '"') inString = true;
      if (char === "{" || char === "[") {
        if (depth === 0) start = i + 1;
        depth++;
      }
      if (depth === 1 && (char === "," || char === "}")) {
        const field = text.slice(start, i).trim();
        if (field) {
          const entries = Object.entries(JSON.parse("{" + field + "}"));
          for (const [key, value] of entries) onField(key, value);
        }
        start = i + 1;
      }
      if (char === "}" || char === "]") depth--;
    }
  };
}
