import path from "node:path";
import { installWhisperCpp, downloadWhisperModel } from "@remotion/install-whisper-cpp";
const to = path.join(process.cwd(), "whisper.cpp");
await installWhisperCpp({ to, version: "1.5.5" });
await downloadWhisperModel({ model: "base.en", folder: to });
console.log("whisper ready");
