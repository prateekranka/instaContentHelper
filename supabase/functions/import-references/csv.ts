import type { ParsedInputRow } from "./types.ts";

const KNOWN_COLUMNS = new Set([
  "handle",
  "url",
  "display_name",
  "notes",
  "tags",
  "region",
]);

export function parsedRowsFromPaste(rawText: string): ParsedInputRow[] {
  return rawText
    .split(/\r?\n/)
    .map((line, index) => ({ line, lineNumber: index + 1 }))
    .filter(({ line }) => line.trim().length > 0)
    .map(({ line, lineNumber }) => ({
      lineNumber,
      rawInput: line.trim(),
      values: [line.trim()],
    }));
}

export function parsedRowsFromCSV(rawText: string): ParsedInputRow[] {
  const records = parseCSV(rawText)
    .map((cells, index) => ({ cells, lineNumber: index + 1 }))
    .filter(({ cells }) => cells.some((cell) => cell.trim().length > 0));

  if (records.length === 0) {
    return [];
  }

  const possibleHeaders = records[0].cells.map(normalizeColumnName);
  const hasHeader = possibleHeaders.some((column) => KNOWN_COLUMNS.has(column));
  const headers = hasHeader
    ? possibleHeaders
    : records[0].cells.map((_, index) => `column_${index + 1}`);
  const dataRecords = hasHeader ? records.slice(1) : records;

  return dataRecords.map(({ cells, lineNumber }) => {
    const columns: Record<string, string> = {};
    const unknownColumns: Record<string, string> = {};

    cells.forEach((cell, index) => {
      const key = headers[index] || `column_${index + 1}`;
      const value = cell.trim();
      if (!value) return;

      columns[key] = value;
      if (!KNOWN_COLUMNS.has(key)) {
        unknownColumns[key] = value;
      }
    });

    const values = [
      ...Object.entries(columns)
        .sort(([left], [right]) =>
          knownColumnRank(left) - knownColumnRank(right)
        )
        .map(([, value]) => value),
    ];

    return {
      lineNumber,
      rawInput: cells.join(",").trim(),
      values,
      columns,
      unknownColumns,
    };
  }).filter((row) => row.values.some((value) => value.trim().length > 0));
}

export function parseCSV(rawText: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;

  for (let index = 0; index < rawText.length; index += 1) {
    const char = rawText[index];
    const next = rawText[index + 1];

    if (char === '"') {
      if (inQuotes && next === '"') {
        field += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === "," && !inQuotes) {
      row.push(field);
      field = "";
    } else if ((char === "\n" || char === "\r") && !inQuotes) {
      if (char === "\r" && next === "\n") {
        index += 1;
      }
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }

  row.push(field);
  rows.push(row);

  return rows;
}

function normalizeColumnName(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function knownColumnRank(column: string): number {
  switch (column) {
    case "url":
      return 0;
    case "handle":
      return 1;
    case "display_name":
      return 2;
    case "notes":
      return 3;
    case "tags":
      return 4;
    case "region":
      return 5;
    default:
      return 10;
  }
}
