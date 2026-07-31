// shell.js — Interactive zsh REPL
// Fake shell with filesystem simulation, command handling, and Claude easter egg trigger.

export function createShell({ body, addLine, killCursors, startClaude }) {
    let buf = '';

    // ── Data (must be before headline — avoids TDZ) ──

    const cmds = {
        ls: (a) => {
            const fs = {
                '~': ['projects', '.aura-distill', '.claude', '.codex', 'Documents'],
                '~/.aura-distill': ['SPINE.md', 'craft', 'ops', 'profile'],
                '~/.claude': ['CLAUDE.md', 'commands', 'rules'],
                '~/.codex': ['AGENTS.md'],
            };
            return (fs[a] || fs['~']).map(f => f.includes('.') ? f : `<span style="color:#7aa2f7">${f}/</span>`).join('  ');
        },
        pwd: () => '/Users/visitor/projects/backend',
        whoami: () => 'visitor',
        echo: (a) => a || '',
        cat: (a) => {
            if (a && a.includes('SPINE')) return '<span style="color:#565f89"># Distill Knowledge Index</span>\n- [Kafka patterns](craft/kafka-patterns.md)\n- [Code style](craft/code-style.md)\n- [Working style](profile/working-style.md)';
            if (a && a.includes('.zshrc')) return '<span style="color:#565f89"># lol nice try</span>';
            return `<span style="color:#f72585">cat: ${a || ''}: No such file</span>`;
        },
        clear: () => '__CLEAR__',
        help: () => '<span style="color:#565f89">ls, pwd, cat, echo, clear, whoami, neofetch, sudo, vim, claude</span>',
        sudo: () => '<span style="color:#f72585">visitor is not in the sudoers file. This incident will be reported.</span>',
        vim: () => '<span style="color:#565f89">Why would you do that to yourself?</span>',
        rm: (a) => (a && a.includes('-rf')) ? '<span style="color:#f72585">rm: nice try, but no.</span>' : '',
        neofetch: () => '<span style="color:#bb9af7">  .---.  </span>visitor@distill\n<span style="color:#bb9af7"> / O O \\ </span>OS: macOS 15.4 | Memory: \u221E (distilled)',
        exit: () => '<span style="color:#565f89">logout\n[Process completed]</span>',
    };

    // ── Headline ──

    let cur = prompt();
    return { prompt, exec, getBuffer, setBuffer, getCurrentLine };

    // ── Public API ──

    function getBuffer() { return buf; }
    function setBuffer(v) { buf = v; }
    function getCurrentLine() { return cur; }

    function prompt() {
        killCursors();
        const l = document.createElement('div');
        l.className = 'term-line visible';
        l.innerHTML = '<span class="term-prompt">$ </span><span class="term-shell-input"></span><span class="term-cursor"></span>';
        body.appendChild(l);
        body.scrollTop = body.scrollHeight;
        return l;
    }

    function exec(cmd) {
        const t = cmd.trim();
        if (!t) return;
        const [c, ...r] = t.split(/\s+/);
        if (c === 'claude') { startClaude(); return; }
        if (cmds[c]) {
            const o = cmds[c](r.join(' '));
            if (o === '__CLEAR__') { body.innerHTML = ''; cur = prompt(); return; }
            if (o) { appendOutput(o); }
        } else {
            addLine(`<span style="color:#f72585">zsh: command not found: ${c}</span>`);
        }
        cur = prompt();
    }

    // ── Private: Output rendering ──

    function appendOutput(html) {
        const el = document.createElement('div');
        el.className = 'term-line visible';
        el.style.whiteSpace = 'pre-wrap';
        el.innerHTML = html;
        body.appendChild(el);
    }
}
