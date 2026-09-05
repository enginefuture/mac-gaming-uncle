# GPTK download channel

The free, noncommercial Mac Gaming Uncle application downloads the original
`Evaluation_environment_for_Windows_games_4.0_beta_2.dmg` separately from its
application and Wine runtime. The image is not modified or repackaged.

- Storage: Cloudflare R2, bucket `apps`, custom domain `download.pingclaws.com`.
- Object prefix: `mac-gaming-uncle/gptk/4.0b2/6248a0edc61553790753e5e9c060b8e53c940ed197f11409dcc34a35e05becc1/`.
- Size: 26,480,358 bytes.
- SHA-256: `6248a0edc61553790753e5e9c060b8e53c940ed197f11409dcc34a35e05becc1`.
- Accompanying license: `License.rtf`, Apple document EA18380, 8/17/2023.

The accompanying license was inspected in this specific image. Section 2A(iii)
permits noncommercial distribution subject to the agreement. Section 2C includes
an exception for distribution of the entire Framework and Redistributables.
This is the engineering basis for this noncommercial distribution channel,
not a claim of unrestricted redistribution rights or legal advice. Other use,
transfer and export restrictions in the original license continue to apply.
Do not reuse this review for another version without inspecting its license.

All original licensing and acknowledgement files remain in the downloaded image.
The client validates the exact size and SHA-256 before mounting, then validates
the DMG and Apple framework signature through GPTKImporter. A failed validation
never proceeds to installation. Successful downloads are retained locally for
retries; interrupted or rejected downloads are not cached as valid installers.

Public R2 access uses the existing custom domain; no bucket access settings or
credentials are embedded in the application. GitHub publication remains separate
from deployment of this download channel.
