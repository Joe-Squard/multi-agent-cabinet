module.exports = {
  apps: [
    {
      name: "cabinet-memory",
      script: "/home/joe/.pyenv/versions/3.12.0/bin/mcp-server-qdrant",
      args: "--transport sse",
      interpreter: "none",
      env: {
        QDRANT_URL: "http://localhost:6333",
        EMBEDDING_PROVIDER: "fastembed",
        EMBEDDING_MODEL: "sentence-transformers/all-MiniLM-L6-v2",
        FASTMCP_PORT: "8000",
      },
      autorestart: true,
      max_restarts: 10,
      restart_delay: 3000,
    },
  ],
};
