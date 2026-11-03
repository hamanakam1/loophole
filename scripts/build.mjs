import { execFileSync } from 'node:child_process';
import { mkdir, copyFile, writeFile } from 'node:fs/promises';
import { build } from 'esbuild';

execFileSync(process.env.GLEAM_BIN || 'gleam', ['build'], { stdio: 'inherit' });
await mkdir('dist', { recursive: true });
await build({
  stdin: { contents: 'import { main } from "./build/dev/javascript/loophole/loophole.mjs"; main();', resolveDir: process.cwd() },
  bundle: true, format: 'esm', target: ['es2022'], minify: true, outfile: 'dist/app.js',
});
for (const file of ['index.html', 'style.css', 'favicon.svg']) {
  await copyFile(`public/${file}`, `dist/${file}`);
}
await writeFile('dist/.nojekyll', '');
console.log('Built browser application in dist/');
