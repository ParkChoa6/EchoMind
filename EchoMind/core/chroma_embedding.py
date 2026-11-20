"""Optional ChromaDB collection embeddings for local Ollama deployments."""

import os


def collection_embedding_options() -> dict:
    model = os.getenv("ECHOMIND_OLLAMA_EMBED_MODEL")
    if not model:
        return {}

    from chromadb.utils.embedding_functions import OllamaEmbeddingFunction

    return {
        "embedding_function": OllamaEmbeddingFunction(
            url=os.getenv("ECHOMIND_OLLAMA_URL", "http://127.0.0.1:11434"),
            model_name=model,
        )
    }
