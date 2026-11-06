// Changed-file selection and invocation shared by the two QML CI entry points.
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';

function git(args) {
    return execFileSync('git', args, {encoding: 'utf8'}).split('\0').filter(Boolean);
}
export function selectFiles(args) {
    let files;
    if (args[0] === '--base') {
        if (args.length !== 2 || !args[1] || args[1].startsWith('-'))
            throw new Error('Usage: --base <commit>');
        files = git(['diff', '--name-only', '-z', '--diff-filter=ACMR', `${args[1]}...HEAD`, '--']);
    } else if (args[0] === '--all' || args.length === 0) {
        files = args[0] === '--all'
            ? git(['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', 'shell', 'shared', 'apps'])
            : [...git(['diff', '--name-only', '-z', '--diff-filter=ACMR', 'HEAD', '--']),
               ...git(['ls-files', '-z', '--others', '--exclude-standard'])];
    } else {
        if (args.some(arg => arg.startsWith('-'))) throw new Error('Unknown argument');
        // Explicit paths are supported without passing them through a shell.
        files = args.flatMap(path => existsSync(path) && statSync(path).isDirectory()
            ? git(['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', path]) : [path]);
    }
    return [...new Set(files)].filter(file => file.endsWith('.qml') && existsSync(file));
}
export function lint(args, duplicateChecks = false) {
    try {
        const files = selectFiles(args);
        const executable = process.env.QMLLINT || 'qmllint';
        // Fail closed even for an empty diff if the configured tool is missing.
        const version = spawnSync(executable, ['--version'], {encoding: 'utf8'});
        if (version.error || version.status !== 0) throw new Error(`Cannot run ${executable}: ${version.error?.message || version.stderr}`);
        console.log(version.stdout.trim());
        let failed = false;
        for (const file of files) {
            // Syntax errors are unconditional. Do not suppress errors near ?./??:
            // the Qt 6 SDK supports those expressions. Type/import checks belong
            // to compiled application tests, which have the generated qmltypes.
            const options = ['--ignore-settings', '--only-explicit-categories'];
            if (duplicateChecks) options.push('--duplicate-property-binding=error', '--duplicated-name=error');
            const result = spawnSync(executable, [...options, '-I', 'shared/qml', '-I', 'shell', '-I', '.', file], {encoding: 'utf8'});
            if (result.error || result.status !== 0) {
                failed = true;
                console.error(`${file}:\n${result.stdout || ''}${result.stderr || ''}${result.error?.message || ''}`);
            }
        }
        console.log(`${duplicateChecks ? 'QML declarations' : 'QML syntax'}: ${files.length} files, ${failed ? 'FAILED' : 'OK'}`);
        process.exitCode = failed ? 1 : 0;
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
