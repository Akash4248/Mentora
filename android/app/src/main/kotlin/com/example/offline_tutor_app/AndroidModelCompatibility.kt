package com.example.offline_tutor_app

internal object AndroidModelCompatibility {
    fun isDFlashDraft(fileName: String): Boolean =
        fileName.contains("dflash", ignoreCase = true)

    fun dflashDraftError(fileName: String): String? {
        if (!isDFlashDraft(fileName)) {
            return null
        }

        return "This Bonsai DFlash2 file is a draft model, not a standalone chat model. Select the matching Bonsai base GGUF instead. Bonsai 2 4B Q2_0 is recommended for phones."
    }
}
