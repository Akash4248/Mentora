package com.example.offline_tutor_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidModelCompatibilityTest {
    @Test
    fun identifiesDFlashDraftFilesWithoutCaseSensitivity() {
        assertTrue(AndroidModelCompatibility.isDFlashDraft("Ternary-Bonsai-2-9B-DFlash2-Q8_0.gguf"))
        assertTrue(AndroidModelCompatibility.isDFlashDraft("bonsai_dflash.gguf"))
    }

    @Test
    fun allowsStandaloneBonsaiBaseModels() {
        assertNull(AndroidModelCompatibility.dflashDraftError("Ternary-Bonsai-2-4B-Q2_0.gguf"))
    }

    @Test
    fun explainsWhyDraftFilesCannotBeLoadedAlone() {
        val error = AndroidModelCompatibility.dflashDraftError("Ternary-Bonsai-2-9B-DFlash2-Q8_0.gguf")

        assertEquals(
            "This Bonsai DFlash2 file is a draft model, not a standalone chat model. Select the matching Bonsai base GGUF instead. Bonsai 2 4B Q2_0 is recommended for phones.",
            error,
        )
    }
}
