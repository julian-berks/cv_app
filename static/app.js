const { createApp } = Vue;

createApp({
    data() {
        return {
            question: '',
            loading: false,
            messages: [
                { role: 'bot', text: "Hi! Ask me anything about Julian's experience." }
            ]
        };
    },
    methods: {
        async ask() {
            const question = this.question.trim();
            if (!question || this.loading) return;

            this.messages.push({ role: 'user', text: question });
            this.question = '';
            this.loading = true;
            this.scrollToBottom();

            try {
                const res = await fetch('ask', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ question })
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
                el.scrollTop = el.scrollHeight;
            });
        }
    }
}).mount('#app');
