import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { transformSync } from '@lwc/compiler';
import { ApexParserFactory, ApexErrorListener } from '@apexdevtools/apex-parser';

const root = resolve(import.meta.dirname, '../force-app/main/default');
let errors = 0;
class Listener extends ApexErrorListener {
    constructor(file) { super(); this.file = file; }
    apexSyntaxError(line, column, message) {
        errors++;
        console.error(`${this.file}:${line}:${column}: ${message}`);
    }
}
let apexFiles = 0;
for (const [directory, extension, entryPoint] of [['classes', '.cls', 'compilationUnit'], ['triggers', '.trigger', 'triggerUnit']]) {
    for (const file of readdirSync(resolve(root, directory)).filter((name) => name.endsWith(extension))) {
        const source = readFileSync(resolve(root, directory, file), 'utf8');
        const { parser } = ApexParserFactory.createLexerAndParser(source, new Listener(file));
        parser[entryPoint](); apexFiles++;
    }
}
const component = 'complianceFilingWorkspace';
for (const extension of ['js', 'html', 'css']) {
    const file = `${component}.${extension}`;
    try {
        const result = transformSync(readFileSync(resolve(root, 'lwc', component, file), 'utf8'), file, {
            name: component, namespace: 'c', apiVersion: 65
        });
        for (const warning of result.warnings || []) {
            if (warning.level === 1) { errors++; console.error(`${file}: ${warning.message}`); }
            else console.warn(`${file}: ${warning.message}`);
        }
    } catch (error) { errors++; console.error(`${file}: ${error.message}`); }
}
if (errors) process.exitCode = 1;
else console.log(`Parsed ${apexFiles} Apex files; compiled the LWC JavaScript, template and CSS. Org compilation and Apex runtime tests remain required.`);
