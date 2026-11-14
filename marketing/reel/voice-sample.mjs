import { KokoroTTS } from "kokoro-js";
const tts = await KokoroTTS.from_pretrained("onnx-community/Kokoro-82M-v1.0-ONNX", { dtype: "q8", device: "cpu" });
const text = "Send us your project. We assign a vetted editor and manage the edit from brief to delivery.";
for (const voice of ["af_heart", "am_michael", "bf_emma"]) {
  const audio = await tts.generate(text, { voice });
  await audio.save(`brand/voice-sample-${voice}.wav`);
  console.log("saved", voice);
}
