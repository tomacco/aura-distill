// research-tracker.js — tracks read status, new/updated badges
// Uses localStorage to remember which studies the user has read.

(function() {
    const STORAGE_KEY = 'distill-research-tracker';
    const LAST_VISIT_KEY = 'distill-last-visit';

    // Study metadata: id → { published, version, title }
    const STUDIES = {
        'ab-testing': { published: '2026-05-15', version: 2, title: 'A/B Testing' },
        'memory-rot': { published: '2026-05-15', version: 2, title: 'Memory Rot' },
        'confidence': { published: '2026-05-15', version: 2, title: 'Confidence Scoring' },
        'philosophical': { published: '2026-05-15', version: 1, title: 'Philosophical Frameworks' },
        'cognitive-biases': { published: '2026-05-16', version: 3, title: 'Cognitive Biases Hub' },
        'decision-fatigue': { published: '2026-05-16', version: 2, title: 'Decision Fatigue' },
        'anchoring-bias': { published: '2026-05-16', version: 2, title: 'Anchoring Bias' },
        'loss-aversion': { published: '2026-05-16', version: 1, title: 'Loss Aversion' },
        'authority-bias': { published: '2026-05-16', version: 1, title: 'Authority Bias' },
        'solution-anchoring': { published: '2026-05-16', version: 2, title: 'Solution Anchoring' },
        'tool-reliability': { published: '2026-05-16', version: 1, title: 'Tool Reliability' },
        'recency-bias': { published: '2026-05-17', version: 1, title: 'Recency Bias' },
        'retrieval': { published: '2026-05-16', version: 1, title: 'Retrieval Hub' },
        'token-economics': { published: '2026-07-09', version: 1, title: 'Token Economics' },
        'model-routing': { published: '2026-07-09', version: 1, title: 'Model Routing' },
        'changelog': { published: '2026-05-17', version: 2, title: 'Changelog' },
    };

    function getTracker() {
        try {
            return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {};
        } catch { return {}; }
    }

    function saveTracker(data) {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    }

    function getLastVisit() {
        return localStorage.getItem(LAST_VISIT_KEY) || '2000-01-01';
    }

    function updateLastVisit() {
        localStorage.setItem(LAST_VISIT_KEY, new Date().toISOString().split('T')[0]);
    }

    // Detect current page ID from filename
    function getCurrentPageId() {
        const path = window.location.pathname;
        const file = path.split('/').pop().replace('.html', '');
        return file === '' || file === 'index' ? null : file;
    }

    // Mark current page as read
    function markAsRead(pageId) {
        if (!pageId || !STUDIES[pageId]) return;
        const tracker = getTracker();
        tracker[pageId] = {
            readAt: new Date().toISOString(),
            version: STUDIES[pageId].version
        };
        saveTracker(tracker);
    }

    // Check if a study is new (published after last visit)
    function isNew(pageId) {
        const lastVisit = getLastVisit();
        const study = STUDIES[pageId];
        if (!study) return false;
        return study.published > lastVisit;
    }

    // Check if a study was updated since last read
    function isUpdated(pageId) {
        const tracker = getTracker();
        const study = STUDIES[pageId];
        if (!study || !tracker[pageId]) return false;
        return study.version > tracker[pageId].version;
    }

    // Check if unread
    function isUnread(pageId) {
        const tracker = getTracker();
        return !tracker[pageId];
    }

    // Add badges to links on index/hub pages
    function addBadges() {
        const links = document.querySelectorAll('a[href$=".html"]');
        links.forEach(link => {
            const href = link.getAttribute('href');
            if (!href) return;
            const pageId = href.replace('.html', '').replace('./', '');
            if (!STUDIES[pageId]) return;

            // Create badge
            let badge = null;
            if (isNew(pageId) && isUnread(pageId)) {
                badge = createBadge('NEW', 'new');
            } else if (isUpdated(pageId)) {
                badge = createBadge('UPDATED', 'updated');
            } else if (isUnread(pageId)) {
                badge = createBadge('UNREAD', 'unread');
            }

            if (badge) {
                // Find a good insertion point (title or first child)
                const title = link.querySelector('.paper-title, .bias-name, td');
                if (title) {
                    title.appendChild(badge);
                } else {
                    link.appendChild(badge);
                }
            }
        });
    }

    function createBadge(text, type) {
        const badge = document.createElement('span');
        badge.className = 'tracker-badge tracker-badge--' + type;
        badge.textContent = text;
        return badge;
    }

    // Add read progress indicator on detail pages
    function addReadIndicator() {
        const pageId = getCurrentPageId();
        if (!pageId || !STUDIES[pageId]) return;

        const meta = document.querySelector('.meta');
        if (!meta) return;

        const study = STUDIES[pageId];
        const tracker = getTracker();
        const readData = tracker[pageId];

        // Add published date
        const pubDate = document.createElement('span');
        pubDate.className = 'tracker-pub-date';
        pubDate.textContent = ' · Published ' + study.published;
        meta.appendChild(pubDate);

        if (readData && !isUpdated(pageId)) {
            const readMark = document.createElement('span');
            readMark.className = 'tracker-read-mark';
            readMark.textContent = ' · ✓ Read';
            meta.appendChild(readMark);
        } else if (isUpdated(pageId)) {
            const updatedMark = document.createElement('span');
            updatedMark.className = 'tracker-updated-mark';
            updatedMark.textContent = ' · Updated since last read';
            meta.appendChild(updatedMark);
        }
    }

    // Inject styles
    function injectStyles() {
        const style = document.createElement('style');
        style.textContent = `
            .tracker-badge {
                display: inline-block;
                font-family: 'JetBrains Mono', monospace;
                font-size: 0.55rem;
                letter-spacing: 0.08em;
                padding: 0.15rem 0.45rem;
                border-radius: 3px;
                margin-left: 0.6rem;
                vertical-align: middle;
                font-weight: 500;
            }
            .tracker-badge--new {
                background: rgba(74, 222, 128, 0.12);
                color: var(--positive);
                border: 1px solid var(--positive);
            }
            .tracker-badge--updated {
                background: rgba(196, 154, 108, 0.12);
                color: var(--accent);
                border: 1px solid var(--accent);
            }
            .tracker-badge--unread {
                background: var(--surface);
                color: var(--dim);
                border: 1px solid var(--border);
            }
            .tracker-pub-date {
                opacity: 0.7;
            }
            .tracker-read-mark {
                color: var(--positive);
            }
            .tracker-updated-mark {
                color: var(--accent);
            }
        `;
        document.head.appendChild(style);
    }

    let _readTimerSet = false;
    const _pageViewStart = Date.now();

    // Remove existing badges (for re-render on back navigation)
    function clearBadges() {
        document.querySelectorAll('.tracker-badge, .tracker-pub-date, .tracker-read-mark, .tracker-updated-mark').forEach(el => el.remove());
    }

    // Init
    function init() {
        injectStyles();
        render();
    }

    function render() {
        clearBadges();

        const pageId = getCurrentPageId();

        // On index/hub pages: show badges
        if (!pageId || pageId === 'index' || pageId === 'cognitive-biases' || pageId === 'retrieval') {
            addBadges();
        }

        // On detail pages: mark as read + show indicator
        if (pageId && STUDIES[pageId]) {
            addReadIndicator();
            // Mark as read after 3 seconds (ensures they actually looked)
            if (!_readTimerSet) {
                _readTimerSet = true;
                setTimeout(() => markAsRead(pageId), 3000);
                // Also mark on pagehide (user navigating away after viewing)
                window.addEventListener('pagehide', function() {
                    if (_pageViewStart && (Date.now() - _pageViewStart > 2000)) {
                        markAsRead(pageId);
                    }
                }, { once: true });
            }
        }

        // Update last visit timestamp
        updateLastVisit();
    }

    // Re-render on back/forward navigation (always, not just bfcache)
    window.addEventListener('pageshow', function() {
        render();
    });

    // Also re-render on popstate (history navigation without full page load)
    window.addEventListener('popstate', function() {
        render();
    });

    // Also re-render on visibility change (tab switch back)
    document.addEventListener('visibilitychange', function() {
        if (!document.hidden) {
            render();
        }
    });

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
