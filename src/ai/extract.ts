export interface ExtractedGame {
  title?: string;
  tagline?: string;
  html?: string;
  /** False when the response stopped mid-way through the code. */
  complete: boolean;
}

/** Pull the title, tagline and HTML document out of a (possibly partial) AI reply. */
export function extractGame(text: string): ExtractedGame {
  const title = /^\s*\**TITLE:?\**\s*(.+)$/im.exec(text)?.[1]?.replace(/\*+/g, '').trim();
  const tagline = /^\s*\**TAGLINE:?\**\s*(.+)$/im.exec(text)?.[1]?.replace(/\*+/g, '').trim();

  let html: string | undefined;
  let complete = false;
  const fence = /```[ \t]*(?:html|HTML)?[ \t]*\r?\n/.exec(text);
  if (fence) {
    const start = fence.index + fence[0].length;
    const end = text.indexOf('```', start);
    if (end >= 0) {
      html = text.slice(start, end);
      complete = true;
    } else {
      html = text.slice(start);
      complete = /<\/html>\s*$/i.test(html);
    }
  } else {
    const doc = /<!doctype html[\s\S]*?<\/html>|<html[\s\S]*?<\/html>/i.exec(text);
    if (doc) {
      html = doc[0];
      complete = true;
    } else {
      const open = /<!doctype html|<html/i.exec(text);
      if (open) html = text.slice(open.index);
    }
  }
  html = html?.trim();
  if (html && !/<(html|body|canvas|script)/i.test(html)) html = undefined;
  const docTitle = html ? /<title[^>]*>([^<]*)<\/title>/i.exec(html)?.[1]?.trim() : undefined;
  return { title: title || docTitle || undefined, tagline, html: html || undefined, complete: !!html && complete };
}
