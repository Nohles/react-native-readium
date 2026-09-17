package com.reactnativereadium.utils.extensions

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class InputStreamToFileTest {

  @get:Rule
  val tempFolder = TemporaryFolder()

  @Test
  fun writesEmptyStreamToEmptyFile() = runBlocking {
    val target = tempFolder.newFile("empty.bin")

    ByteArrayInputStream(ByteArray(0)).toFile(target.absolutePath)

    assertTrue(target.exists())
    assertEquals(0, target.length())
  }

  @Test
  fun writesSingleByteStream() = runBlocking {
    val target = tempFolder.newFile("single.bin")

    ByteArrayInputStream(byteArrayOf(0x2A)).toFile(target.absolutePath)

    assertEquals(1, target.length())
    assertEquals(0x2A, target.readBytes()[0].toInt())
  }

  @Test
  fun writesMultiChunkStreamToDisk() = runBlocking {
    val data = ByteArray(1024 * 1024) { (it % 251).toByte() }
    val target = tempFolder.newFile("large.bin")

    ByteArrayInputStream(data).toFile(target.absolutePath)

    assertTrue(data.contentEquals(target.readBytes()))
  }

  @Test
  fun overwritesExistingFileContent() = runBlocking {
    val target = tempFolder.newFile("existing.bin")
    target.writeBytes(ByteArray(2048) { 0x1F })

    ByteArrayInputStream("replaced".toByteArray()).toFile(target.absolutePath)

    assertEquals("replaced", target.readText())
  }

  @Test
  fun createsFileWhenTargetDoesNotExist() = runBlocking {
    val target = File(tempFolder.root, "created.bin")

    ByteArrayInputStream("content".toByteArray()).toFile(target.absolutePath)

    assertTrue(target.exists())
    assertEquals("content", target.readText())
  }

  @Test
  fun closesInputStreamAfterCompletion() = runBlocking {
    val target = tempFolder.newFile("closed.bin")
    val input = CheckedInputStream(ByteArrayInputStream("data".toByteArray()))

    input.toFile(target.absolutePath)

    assertTrue(input.isClosed)
    assertEquals("data", target.readText())
  }

  @Test
  fun closesInputStreamWhenTargetCannotBeOpened() {
    val input = CheckedInputStream(ByteArrayInputStream("data".toByteArray()))
    val target = tempFolder.newFolder("occupied")

    assertThrows(IOException::class.java) {
      runBlocking { input.toFile(target.absolutePath) }
    }

    assertTrue(input.isClosed)
  }

  @Test
  fun closesInputStreamWhenParentDirectoryDoesNotExist() {
    val input = CheckedInputStream(ByteArrayInputStream("data".toByteArray()))
    val target = File(tempFolder.root, "missing/created.bin")

    assertThrows(IOException::class.java) {
      runBlocking { input.toFile(target.absolutePath) }
    }

    assertTrue(input.isClosed)
  }

  @Test
  fun closesInputAndOutputWhenReadingFails() {
    val target = tempFolder.newFile("failure.bin")
    val input = CheckedInputStream(object : InputStream() {
      override fun read(): Int = throw IOException("Read failed")
    })

    assertThrows(IOException::class.java) {
      runBlocking { input.toFile(target.absolutePath) }
    }

    assertTrue(input.isClosed)
    assertTrue(target.delete())
  }

  @Test
  fun writesBinaryPayloadWithNullBytes() = runBlocking {
    val data = byteArrayOf(0x00, 0x01, 0x00, 0xFF.toByte(), 0x00)
    val target = tempFolder.newFile("binary.bin")

    ByteArrayInputStream(data).toFile(target.absolutePath)

    assertTrue(data.contentEquals(target.readBytes()))
  }

  private class CheckedInputStream(
    private val delegate: InputStream
  ) : InputStream() {
    var isClosed = false
      private set

    override fun read(): Int = delegate.read()

    override fun close() {
      isClosed = true
      delegate.close()
    }
  }
}
