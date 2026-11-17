import { z } from "zod";

import { AVATAR_MAX_BYTES, AVATAR_TYPES } from "./avatar";

// Checks what the browser declared. The server action then checks the real type from the bytes.
export const avatarUploadSchema = z.object({
  avatar: z
    .file({ error: "Choose a picture to upload." })
    .min(1, { error: "Choose a picture to upload." })
    .max(AVATAR_MAX_BYTES, { error: "That picture is larger than 2 MB." })
    .mime(Object.values(AVATAR_TYPES), { error: "Upload a JPEG, PNG or WebP picture." }),
});
