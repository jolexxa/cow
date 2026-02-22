// cow_mlx.h — Flat C API for MLX inference, designed for Dart FFI.
//
// All functions are synchronous and blocking. Async MLX operations are
// bridged internally via a dedicated dispatch queue + semaphore.
//
// Handles are int32 indices into a global registry (not raw pointers),
// making them safe to share across Dart isolates.

#ifndef COW_MLX_H
#define COW_MLX_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------- Constants ----------

#define COW_MLX_INVALID_HANDLE ((int32_t)-1)

// ---------- Error handling ----------

/// Get the last error message for the calling thread.
/// Returns NULL if no error. The returned pointer is valid until the next
/// cow_mlx call on the same thread.
const char* cow_mlx_get_error(void);

// ---------- Lifecycle ----------

/// Initialize the MLX backend. Call once before any other calls.
/// Returns true on success.
bool cow_mlx_init(void);

/// Shut down the MLX backend. Call once at program exit.
void cow_mlx_shutdown(void);

// ---------- Model loading ----------

/// Progress callback for model loading.
/// @param progress Fraction complete, 0.0 to 1.0.
/// @param user_data Opaque pointer passed through from cow_mlx_load_model.
/// @return true to continue loading, false to cancel.
typedef bool (*cow_mlx_progress_fn)(float progress, void* user_data);

/// Load a model from a local HuggingFace-format directory.
/// The directory should contain config.json, tokenizer.json, and
/// .safetensors weight files (standard mlx-community format).
///
/// @param model_path Absolute path to the model directory.
/// @param progress_cb Optional progress callback (may be NULL).
/// @param user_data Opaque pointer forwarded to progress_cb.
/// @return Model handle, or COW_MLX_INVALID_HANDLE on failure.
int32_t cow_mlx_load_model(
    const char* model_path,
    cow_mlx_progress_fn progress_cb,
    void* user_data
);

/// Free a loaded model. Invalidates the handle.
void cow_mlx_free_model(int32_t model);

/// Get a shareable integer ID for a model handle.
/// This ID can be sent to another Dart isolate and used with
/// cow_mlx_model_from_id to reconstruct the handle.
int64_t cow_mlx_model_get_id(int32_t model);

/// Reconstruct a model handle from an ID obtained via cow_mlx_model_get_id.
/// The model must still be alive (not freed).
/// Returns COW_MLX_INVALID_HANDLE if the ID is unknown.
int32_t cow_mlx_model_from_id(int64_t model_id);

// ---------- Context (generation session) ----------

/// Create an inference context for a model.
/// @param model Model handle.
/// @param max_tokens Maximum context window size (0 = model default).
/// @return Context handle, or COW_MLX_INVALID_HANDLE on failure.
int32_t cow_mlx_create_context(int32_t model, int32_t max_tokens);

/// Free a context. Invalidates the handle.
void cow_mlx_free_context(int32_t context);

/// Reset context state (clears iterator, detokenizer, and stop tokens).
/// @return true on success.
bool cow_mlx_reset_context(int32_t context);

// ---------- Tokenization ----------

/// Tokenize text into token IDs.
/// @param model Model handle.
/// @param text UTF-8 text to tokenize.
/// @param text_len Length of text in bytes.
/// @param out_tokens Caller-allocated output buffer (may be NULL to query size).
/// @param max_tokens Size of out_tokens buffer.
/// @param add_special Whether to add BOS/EOS special tokens.
/// @return Number of tokens produced. Negative if buffer too small
///         (absolute value = required size). -1 on error.
int32_t cow_mlx_tokenize(
    int32_t model,
    const char* text,
    int32_t text_len,
    int32_t* out_tokens,
    int32_t max_tokens,
    bool add_special
);

/// Check if a token is an end-of-generation token.
bool cow_mlx_is_eog(int32_t model, int32_t token);

// ---------- Generation ----------

/// Begin a generation session. Processes the prompt tokens through
/// the model (prefill) and prepares for token-by-token generation.
///
/// Internally creates a TokenIterator (from MLXLMCommon) which handles
/// prefill, KV cache management, and asyncEval GPU pipelining.
///
/// The native side compares incoming tokens against the cached token
/// sequence to find the common prefix. Only tokens after the prefix
/// are prefilled, and the cache is trimmed if it diverged.
///
/// Sampling parameters are passed as individual arguments:
/// @param context Context handle.
/// @param tokens Array of prompt token IDs.
/// @param token_count Number of prompt tokens.
/// @param temperature Sampling temperature (0.0 = greedy).
/// @param top_p Top-P nucleus sampling (1.0 = disabled).
/// @param top_k Top-K filtering (0 = disabled).
/// @param min_p Min-P filtering (0.0 = disabled).
/// @param repeat_penalty Repetition penalty (1.0 = disabled).
/// @param repeat_window Number of recent tokens for repetition penalty.
/// @param seed RNG seed (0 = random).
/// @return true on success.
bool cow_mlx_generate_begin(
    int32_t context,
    const int32_t* tokens,
    int32_t token_count,
    float temperature,
    float top_p,
    int32_t top_k,
    float min_p,
    float repeat_penalty,
    int32_t repeat_window,
    int32_t seed
);

/// Generate the next text chunk.
///
/// Advances the TokenIterator by one token, feeds it through the
/// streaming detokenizer, and writes any complete UTF-8 text to buf.
///
/// @param context Context handle.
/// @param buf Caller-allocated output buffer (may be NULL to query size).
/// @param buf_len Size of buf.
/// @return Number of UTF-8 bytes written.
///         0 if the token produced an incomplete character (e.g. partial emoji).
///         -1 if generation is done (EOG token or max tokens reached).
///         Negative (< -1) if buffer too small (absolute value = required size).
int32_t cow_mlx_generate_next(
    int32_t context,
    char* buf,
    int32_t buf_len
);

// ---------- KV Cache Management ----------

/// Get the number of tokens currently cached in the KV cache.
/// Returns -1 on error (invalid handle).
int32_t cow_mlx_cache_token_count(int32_t context);

/// Trim n tokens from the END of the KV cache (undo).
/// Returns actual number of tokens trimmed, or -1 on error.
int32_t cow_mlx_cache_trim_end(int32_t context, int32_t n);

/// Trim n tokens from the FRONT of the KV cache (sliding window eviction).
/// Returns actual number of tokens trimmed, or -1 on error.
int32_t cow_mlx_cache_trim_front(int32_t context, int32_t n);

#ifdef __cplusplus
}
#endif

#endif // COW_MLX_H
