# Search visibility

Konevo's public product page is designed to be indexed. This guide records the
search-discovery behavior that is already included and what an operator must do
after deploying to a real public domain.

## Included in the application

- The public landing page, Privacy Policy, and Terms have titles, descriptions,
  canonical URLs, Open Graph metadata, and Twitter sharing metadata.
- Shared links use `images/landing_small.png` as their preview image.
- The public landing page includes `SoftwareApplication` structured data based
  only on current product capabilities.
- `/sitemap.xml` lists the public landing, Privacy Policy, and Terms pages.
- `/robots.txt` allows public discovery, points crawlers to the sitemap, and
  excludes application, account, upload, and integration routes.
- Account and application pages default to `noindex, nofollow`.

## Deployment requirements

Set `PHX_HOST` to the final public hostname before releasing. Konevo uses the
endpoint URL derived from that setting for canonical URLs, sitemap entries, and
social-preview URLs. Serve the site over HTTPS.

After the domain is live:

1. Open `/robots.txt` and `/sitemap.xml` in a browser and ensure every URL uses
   the final HTTPS hostname.
2. Share the landing-page URL in a messaging or social-preview debugger and
   confirm that the title, description, and landing image are shown.
3. Verify the domain in Google Search Console and submit
   `https://<PHX_HOST>/sitemap.xml`.
4. Monitor indexing, Search Console queries, and page performance before adding
   more public pages.

## Content policy

Konevo should target precise, truthful language such as “self-hosted AI CRM for
Gmail”, “email to task”, and “AI email replies for review”. Do not call it open
source, claim a hosted service, or create thin keyword pages. Add a dedicated
public page only when it explains a real, supported workflow in enough detail to
help a prospective operator.
