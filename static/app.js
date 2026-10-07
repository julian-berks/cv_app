const { createApp } = Vue;

const MARKED_SRC = 'https://unpkg.com/marked@12/marked.min.js';
const PURIFY_SRC = 'https://unpkg.com/dompurify@3/dist/purify.min.js';
const MERMAID_SRC = 'https://unpkg.com/mermaid@11/dist/mermaid.min.js';

const scriptLoads = {};

async function sha256Hex(text) {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
}
function loadScript(src) {
    if (!scriptLoads[src]) {
        scriptLoads[src] = new Promise((resolve, reject) => {
            const el = document.createElement('script');
            el.src = src;
            el.onload = resolve;
            el.onerror = () => {
                delete scriptLoads[src];
                reject(new Error(`Failed to load ${src}`));
            };
            document.head.appendChild(el);
        });
    }
    return scriptLoads[src];
}

function renderMarkdown(markdown) {
    const html = DOMPurify.sanitize(marked.parse(markdown));
    const doc = new DOMParser().parseFromString(html, 'text/html');

    doc.querySelectorAll('pre > code.language-mermaid').forEach(code => {
        const diagram = doc.createElement('div');
        diagram.className = 'mermaid';
        diagram.textContent = code.textContent;
        code.parentElement.replaceWith(diagram);
    });

    // Links to repository files don't resolve on the website, so show them as plain code.
    doc.querySelectorAll('a').forEach(link => {
        if (/^(https?:|#)/.test(link.getAttribute('href') || '')) return;
        const code = doc.createElement('code');
        code.textContent = link.textContent;
        link.replaceWith(code);
    });

    return doc.body.innerHTML;
}

createApp({
    data() {
        return {
            view: 'home',
            question: '',
            loading: false,
            aboutHtml: '',
            aboutLoading: false,
            aboutError: '',
            messages: [
                { role: 'bot', text: "Hi! Ask me anything about Julian's experience." }
            ]
        };
    },
    methods: {
        show(view) {
            this.view = view;
            if (view === 'chat') this.scrollToBottom();
            if (view === 'about') this.loadAbout();
        },
        async loadAbout() {
            if (this.aboutHtml || this.aboutLoading) return;
            this.aboutLoading = true;
            this.aboutError = '';
            try {
                const [res] = await Promise.all([
                    fetch('architecture.md'),
                    loadScript(MARKED_SRC),
                    loadScript(PURIFY_SRC),
                    loadScript(MERMAID_SRC)
                ]);
                if (!res.ok) throw new Error(`Request failed (${res.status})`);
                this.aboutHtml = renderMarkdown(await res.text());
                // Mermaid measures the DOM, so diagrams render only once the page is visible.
                await this.$nextTick();
                mermaid.initialize({ startOnLoad: false });
                await mermaid.run({ nodes: this.$refs.about.querySelectorAll('.mermaid') });
            } catch (e) {
                console.error(e);
                this.aboutError = 'Could not load the project documentation. Please try again.';
            } finally {
                this.aboutLoading = false;
            }
        },
        async ask() {
            const question = this.question.trim();
            if (!question || this.loading) return;

            this.messages.push({ role: 'user', text: question });
            this.question = '';
            this.loading = true;
            this.scrollToBottom();

            try {
                const body = JSON.stringify({ question });
                const res = await fetch('ask', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        // CloudFront needs the body hash to sign POSTs to a Lambda function URL.
                        'x-amz-content-sha256': await sha256Hex(body)
                    },
                    body
                });
                const data = await res.json().catch(() => ({}));

                if (!res.ok) {
                    // FastAPI validation errors return detail as a list, so only show string messages.
                    throw new Error(typeof data.detail === 'string' ? data.detail : `Request failed (${res.status})`);
                }
                this.messages.push({ role: 'bot', text: data.answer });
            } catch (e) {
                this.messages.push({ role: 'error', text: e.message });
            } finally {
                this.loading = false;
                this.scrollToBottom();
            }
        },
        scrollToBottom() {
            this.$nextTick(() => {
                const el = this.$refs.messages;
                // The chat view may be hidden if the user switched to Home mid-request.
                if (el) el.scrollTop = el.scrollHeight;
            });
        }
    }
}).mount('#app');
