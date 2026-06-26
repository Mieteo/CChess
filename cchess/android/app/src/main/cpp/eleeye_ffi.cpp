/*
 * eleeye_ffi.cpp — C-ABI FFI wrapper for the ElephantEye Xiangqi engine.
 *
 * Exposes two functions callable from Dart FFI:
 *   eleeye_init()         — must be called once before any search
 *   eleeye_best_move()    — returns best move in UCI notation ("e0e1")
 *
 * Compiled with -DCCHESS_A3800 so ElephantEye stores its result in
 * Search.mvResult instead of writing to stdout (which the UCCI mode does).
 */

#define CCHESS_A3800   // library mode: result via Search.mvResult, no stdout

#include "eleeye/pregen.h"
#include "eleeye/position.h"
#include "eleeye/hash.h"
#include "eleeye/search.h"

#include <cstring>

// ── Constants from search.h that aren't re-exported ─────────────────────────
static const int INTERRUPT_COUNT = 4096;

// ── Internal one-time init guard ─────────────────────────────────────────────
static bool s_initialized = false;

static void ensureInit() {
    if (s_initialized) return;
    s_initialized = true;

    PreGenInit();

    Search.pos.FromFen(cszStartFen);
    Search.pos.nDistance = 0;
    Search.pos.PreEvaluate();

    Search.nBanMoves   = 0;
    Search.bQuit       = false;
    Search.bBatch      = false;
    Search.bDebug      = false;
    Search.bUseHash    = true;
    Search.bUseBook    = false; // no book file on Android
    Search.bNullMove   = true;
    Search.bKnowledge  = true;
    Search.bIdle       = false;
    Search.nCountMask  = INTERRUPT_COUNT - 1;
    Search.nRandomMask = 0;

    Search.rc4Random.InitRand();
}

extern "C" {

/*
 * Initialize the engine. Safe to call multiple times (idempotent).
 */
void eleeye_init() {
    ensureInit();
}

/*
 * Search for the best move in the given position.
 *
 * Parameters:
 *   fen      — FEN string for the position (standard Xiangqi FEN)
 *   depth    — search depth in plies (4–8 recommended; 6 is a good default)
 *   out_move — caller-allocated buffer receiving the UCI move (e.g. "e0e1\0")
 *   out_len  — size of out_move; must be >= 5
 *
 * Returns 0 on success, -1 on error (no legal move, bad FEN, buffer too small).
 */
int eleeye_best_move(const char* fen, int depth, char* out_move, int out_len) {
    if (!fen || !out_move || out_len < 5 || depth < 1) return -1;

    ensureInit();

    Search.pos.FromFen(fen);
    Search.pos.nDistance = 0;
    Search.pos.PreEvaluate();
    Search.pos.SetIrrev();

    Search.nBanMoves = 0;
    Search.nGoMode   = GO_MODE_INFINITY; // depth-bounded search

    SearchMain(depth);

    int mv = Search.mvResult;
    if (mv == 0) return -1; // no legal move (checkmate / stalemate)

    // MOVE_COORD returns a 4-byte value whose bytes form the UCI string
    uint32_t coord = MOVE_COORD(mv);
    const char* s  = reinterpret_cast<const char*>(&coord);
    out_move[0] = s[0];
    out_move[1] = s[1];
    out_move[2] = s[2];
    out_move[3] = s[3];
    out_move[4] = '\0';

    return 0;
}

} // extern "C"
