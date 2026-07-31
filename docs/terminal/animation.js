// animation.js — GSAP scroll-triggered timeline + distill demo data
// Plays the terminal boot sequence and distill demonstration on scroll.
// Calls onComplete when the exit sequence finishes to hand off to interactive mode.

export function runAnimation(helpers, onComplete) {
    const { addLine, addFadeLine, showFooter, removeFooter, renderBoot, footerType, footerCursor } = helpers;
    const SEP = '\u2500'.repeat(45);

    const tl = gsap.timeline({
        scrollTrigger: { trigger: '#demo-terminal', start: 'bottom bottom', once: true }
    });

    buildTimeline(tl);

    // ── Private: Demo data ──

    function distillLines() {
        return [
            { type: 'blank' },
            { type: 'header', text: '  \u27e1 Retrospective Distillation' },
            { type: 'dim', text: '  Scanning session: 47 messages \u00b7 1h 38m' },
            { type: 'blank' },
            { type: 'separator', text: '  ' + '\u2500'.repeat(46) },
            { type: 'blank' },
            { type: 'header', text: '  SIGNALS DETECTED' },
            { type: 'blank' },
            { type: 'signal', badge: 'correction \u00d73', badgeClass: 'term-type-correction', quote: 'Deploy procedure changed. Stop suggesting the old one.', principle: '[UPDATED] Deploy flow', desc: 'Canary (5m) \u2192 staging (30m) \u2192 prod. Old flow deprecated.' },
            { type: 'blank' },
            { type: 'signal', badge: 'preference', badgeClass: 'term-type-preference', quote: 'Use cursor pagination everywhere', principle: 'API patterns', desc: 'Hardened: 12 confirmations. Assert without hedging.' },
            { type: 'blank' },
            { type: 'signal', badge: 'escalation', badgeClass: 'term-type-escalation', quote: 'This is just 3 events. Why are you proposing a pipeline?', principle: 'Solution proportionality', desc: 'Client-side tracking \u2260 data pipeline. Check where data lives first.' },
            { type: 'blank' },
            { type: 'separator', text: '  ' + '\u2500'.repeat(46) },
            { type: 'blank' },
            { type: 'header', text: '  ENCODED TO' },
            { type: 'blank' },
            { type: 'file', text: '  \u2713 ~/.aura-distill/ops/deploy-procedure.md  [UPDATED]' },
            { type: 'file', text: '  \u2713 ~/.aura-distill/craft/api-patterns.md' },
            { type: 'file', text: '  \u2713 ~/.aura-distill/craft/solution-selection.md  [NEW]' },
            { type: 'blank' },
            { type: 'score', text: '  Memory pressure: 8/10 \u2192 0/10' },
            { type: 'success', text: '  \u2713 3 principles encoded \u00b7 2 files updated \u00b7 1 new' },
            { type: 'blank' },
            { type: 'dim', text: '  Next session will catch outdated deploys and over-engineering.' },
        ];
    }

    function steps() {
        return [
            { act: 'boot' }, { act: 'footer' }, { act: 'wait', t: 0.5 },
            // Scene 1: The pain — user corrects Claude for the THIRD time
            { act: 'line', html: '&nbsp;' },
            { act: 'line', html: '<span style="color:#565f89">  \u2022\u2022\u2022 earlier in the session \u2022\u2022\u2022</span>' },
            { act: 'wait', t: 0.4 },
            { act: 'line', html: '&nbsp;' },
            { act: 'line', html: '<span style="color:#9ece6a">\u276f</span> <span style="color:#c0caf5">Deploy procedure changed last month. Stop suggesting the old one.</span>' },
            { act: 'wait', t: 0.6 },
            { act: 'line', html: '&nbsp;' },
            { act: 'line', html: '<span style="color:#7aa2f7">Claude</span>  <span style="color:#565f89">You\'re right, I apologize. The new procedure is canary \u2192 staging \u2192 prod. I\'ll use that.</span>' },
            { act: 'wait', t: 0.8 },
            { act: 'line', html: '&nbsp;' },
            { act: 'line', html: '<span style="color:#f7768e;font-style:italic">  \u2191 Third time this month you\'ve told me this.</span>' },
            { act: 'wait', t: 1.2 },
            // Scene 2: User runs /distill
            { act: 'line', html: '&nbsp;' },
            { act: 'type', text: '/distill', t: 1.2 }, { act: 'wait', t: 0.3 },
            { act: 'submit', text: '/distill' },
            { act: 'spinner', text: 'Harvesting signals...', t: 1.5 },
            { act: 'output', lines: distillLines() },
            { act: 'wait', t: 0.8 },
            // Scene 3: Next session — it remembers
            { act: 'line', html: '<span style="color:#3b4261">' + '\u2500'.repeat(46) + '</span>' },
            { act: 'line', html: '&nbsp;' },
            { act: 'line', html: '<span style="color:#565f89;font-style:italic">  \u23f3 Next day, new session...</span>' },
            { act: 'wait', t: 0.8 },
            { act: 'line', html: '&nbsp;' },
            { act: 'line', html: '<span style="color:#9ece6a">\u276f</span> <span style="color:#c0caf5">Deploying the fix now. Pushing to staging.</span>' },
            { act: 'wait', t: 0.6 },
            { act: 'line', html: '&nbsp;' },
            { act: 'line', html: '<span style="color:#7aa2f7">Claude</span>  <span style="color:#c0caf5"><b>Hold on</b> \u2014 deploy procedure was updated. The current flow is canary (5 min) \u2192 staging (30 min) \u2192 prod. Want me to walk you through it?</span>' },
            { act: 'wait', t: 0.6 },
            { act: 'line', html: '&nbsp;' },
            { act: 'line', html: '<span style="color:#9ece6a;font-style:italic">  \u2713 Remembered. Without being asked.</span>' },
            { act: 'wait', t: 0.6 }, { act: 'footerReset' }, { act: 'wait', t: 0.8 },
            { act: 'type', text: '/exit', t: 0.8 }, { act: 'wait', t: 0.3 },
            { act: 'submit', text: '/exit' }, { act: 'wait', t: 0.2 },
            { act: 'exit' },
        ];
    }

    // ── Private: Timeline construction ──

    function buildTimeline(tl) {
        steps().forEach(s => {
            switch (s.act) {
                case 'boot': tl.call(renderBoot); tl.to({}, { duration: 0.3 }); break;
                case 'footer': tl.call(() => showFooter()); break;
                case 'wait': tl.to({}, { duration: s.t }); break;
                case 'line': tl.call(() => addLine(s.html)); tl.to({}, { duration: 0.05 }); break;
                case 'type': addTypeStep(tl, s.text, s.t); break;
                case 'submit': addSubmitStep(tl, s.text); break;
                case 'spinner': addSpinnerStep(tl, s.text, s.t); break;
                case 'output': addOutputStep(tl, s.lines); break;
                case 'footerReset': tl.call(() => footerCursor(true)); break;
                case 'exit': addExitStep(tl); break;
            }
        });
    }

    function addTypeStep(tl, text, dur) {
        const chars = text.split('');
        const perChar = dur / chars.length;
        chars.forEach(ch => {
            tl.call(() => {
                const el = document.getElementById('footer-typed');
                if (el) el.textContent += ch;
            });
            tl.to({}, { duration: perChar });
        });
    }

    function addSubmitStep(tl, text) {
        tl.call(() => {
            addLine(`<span style="color:#3b4261">${SEP}</span>`);
            addLine(`<span style="color:#9ece6a">\u276f</span> ${text}`);
            footerType('');
            footerCursor(false);
        });
    }

    function addSpinnerStep(tl, text, duration) {
        tl.call(() => {
            const sl = document.createElement('div');
            sl.className = 'term-line visible';
            sl.id = 'demo-spinner';
            sl.innerHTML = `<span class="term-spinner">  \u280b </span><span class="term-dim">${text}</span>`;
            const body = document.getElementById('terminal-body');
            body.appendChild(sl);
            body.scrollTop = body.scrollHeight;
            const fr = ['\u280b', '\u2819', '\u2839', '\u2838', '\u283c', '\u2834', '\u2826', '\u2827', '\u2807', '\u280f'];
            let i = 0;
            sl._int = setInterval(() => {
                const sp = sl.querySelector('.term-spinner');
                if (sp) sp.textContent = '  ' + fr[i++ % fr.length] + ' ';
            }, 80);
        });
        tl.to({}, { duration });
        tl.call(() => {
            const sl = document.getElementById('demo-spinner');
            if (sl) { clearInterval(sl._int); sl.remove(); }
        });
    }

    function addOutputStep(tl, lines) {
        lines.forEach(ld => {
            tl.call(() => addFadeLine(ld));
            tl.to({}, { duration: ld.type === 'signal' ? 0.25 : ld.type === 'blank' ? 0.04 : 0.1 });
        });
    }

    function addExitStep(tl) {
        tl.call(() => {
            removeFooter();
            addLine('&nbsp;');
            addLine('<span style="color:#565f89">/exit                 Exit the REPL</span>');
            addLine('<span style="color:#565f89">/context              Visualize context usage</span>');
            addLine('<span style="color:#565f89">/memory               Edit Claude memory files</span>');
            addLine('<span style="color:#565f89">/distill              Consolidate session learnings</span>');
            addLine('&nbsp;');
            addLine('<span style="color:#565f89">Resume this session with:</span>');
            addLine('<span style="color:#565f89">claude --resume a1b2c3d4-e5f6-7890-abcd-ef1234567890</span>');
            addLine('<span style="color:#c0caf5">visitor@mac ~ % </span><span class="term-cursor"></span>');
        });
        tl.to({}, { duration: 1.5 });
        tl.call(() => onComplete());
    }
}
