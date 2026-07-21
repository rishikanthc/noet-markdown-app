import Foundation

public struct HTMLDocument {
  public static func wrap(fragment: String) -> String {
    """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root {
          color-scheme: light;
          --paper: #fbfaf8;
          --surface-subtle: #f5f3ef;
          --surface-muted: #ebe8e2;
          --ink: #0f172a;
          --ink-soft: #1e293b;
          --text: #334155;
          --muted: #64748b;
          --faint: #94a3b8;
          --accent: #4f46e5;
          --accent-soft: #eef2ff;
          --orange: #c2410c;
          --code-ink: #3730a3;
          --code-chip: #f1eee9;
        }
        * { box-sizing: border-box; }
        html { background: var(--paper); }
        body {
          max-width: 780px;
          margin: 0 auto;
          padding: 42px 42px 96px;
          color: var(--text);
          background: var(--paper);
          font-family: "Iosevka Etoile", Charter, Georgia, serif;
          font-size: 16px;
          line-height: 1.58;
          overflow-wrap: anywhere;
          text-rendering: optimizeLegibility;
          -webkit-font-smoothing: antialiased;
          counter-reset: section;
        }
        p { margin: 0 0 13px; }
        h1, h2, h3, h4, h5, h6 {
          color: var(--ink);
          font-family: "Iosevka Aile", "Avenir Next", system-ui, sans-serif;
          font-weight: 600;
          line-height: 1.2;
          letter-spacing: -.015em;
        }
        h1 { margin: 58px 0 22px; font-size: 25px; counter-increment: section; counter-reset: subsection; }
        h1::before {
          content: counter(section, decimal-leading-zero);
          margin-right: 14px;
          color: var(--accent);
          font-family: "Iosevka Term Extended", ui-monospace, monospace;
          font-size: .8em;
          font-weight: 400;
        }
        h2 { margin: 40px 0 16px; color: var(--ink-soft); font-size: 20.5px; counter-increment: subsection; }
        h2::before {
          content: counter(section) "." counter(subsection);
          margin-right: 11px;
          color: var(--muted);
          font-family: "Iosevka Term Extended", ui-monospace, monospace;
          font-size: .76em;
          font-weight: 400;
        }
        h3 { margin: 29px 0 11px; font-size: 18px; }
        strong { color: var(--ink); font-weight: 600; }
        em { font-style: italic; }
        del { color: var(--muted); text-decoration-thickness: 1px; }
        mark {
          padding: .04em .28em;
          border-radius: 4px;
          color: inherit;
          background: rgba(254, 243, 199, .82);
        }
        a {
          color: var(--accent);
          text-decoration-color: rgba(79, 70, 229, .2);
          text-underline-offset: 3px;
        }
        code, pre {
          font-family: "Iosevka Term Extended", "SF Mono", Menlo, ui-monospace, monospace;
        }
        :not(pre) > code {
          padding: .08em .32em;
          border-radius: 4px;
          color: var(--code-ink);
          background: var(--code-chip);
          font-size: .94em;
        }
        pre {
          margin: 36px 0;
          padding: 16px 22px;
          overflow: auto;
          border-radius: 7px;
          color: var(--ink-soft);
          background: var(--surface-subtle);
          font-size: 15px;
          line-height: 1.5;
        }
        pre code { padding: 0; color: inherit; background: transparent; }
        blockquote {
          margin: 22px 0;
          padding: 0 11px 0 25px;
          border-left: 2px solid var(--accent);
          color: var(--ink-soft);
          font-style: italic;
        }
        ul, ol { margin: 11px 0 16px; padding-left: 25px; }
        li { margin: 5px 0; }
        li::marker { color: var(--accent); font-family: ui-monospace, monospace; font-weight: 600; }
        img {
          display: block;
          max-width: 100%;
          height: auto;
          margin: 29px auto;
          padding: 12px;
          border-radius: 13px;
          background: var(--surface-subtle);
        }
        .task-list-item { list-style: none; }
        .task-list-item input { accent-color: var(--accent); }
        hr { margin: 36px 0; border: 0; border-top: 1px solid rgba(15, 23, 42, .14); }
        table { border-collapse: collapse; width: 100%; }
        th, td { padding: 7px 11px; border-bottom: 1px solid rgba(15, 23, 42, .10); }
        th { color: var(--ink); font-family: "Iosevka Aile", system-ui, sans-serif; font-weight: 600; }
        @media (max-width: 700px) {
          body { padding: 28px 22px 72px; }
        }
      </style>
    </head>
    <body>\(fragment)</body>
    </html>
    """
  }
}
