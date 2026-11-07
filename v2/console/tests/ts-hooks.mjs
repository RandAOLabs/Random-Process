// Test-only loader: lets `node --test` import the console's .ts/.tsx sources.
// Extensionless relative imports resolve to .ts/.tsx; TypeScript compiles them.
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

export async function resolve(specifier, context, next) {
  if ((specifier.startsWith('./') || specifier.startsWith('../')) && !/\.[cm]?[jt]sx?$/.test(specifier)) {
    for (const ext of ['.ts', '.tsx']) {
      const url = new URL(specifier + ext, context.parentURL);
      if (fs.existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
  }
  return next(specifier, context);
}

export async function load(url, context, next) {
  if (!/\.tsx?$/.test(url)) return next(url, context);
  const source = fs.readFileSync(fileURLToPath(url), 'utf8');
  const out = ts.transpileModule(source, { fileName: fileURLToPath(url), compilerOptions: {
    module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX } });
  return { format: 'module', source: out.outputText, shortCircuit: true };
}
