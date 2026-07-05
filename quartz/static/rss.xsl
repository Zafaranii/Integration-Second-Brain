<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" version="1.0" encoding="UTF-8" indent="yes"/>
  <xsl:template match="/">
    <html xmlns="http://www.w3.org/1999/xhtml" lang="en">
      <head>
        <title><xsl:value-of select="/rss/channel/title"/> (RSS Feed)</title>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <style type="text/css">
          :root {
            --bg-color: #faf8f8;
            --text-color: #2b2b2b;
            --text-muted: #5e5e62;
            --card-bg: rgba(255, 255, 255, 0.85);
            --card-border: rgba(0, 0, 0, 0.08);
            --card-hover-border: #284b63;
            --accent-color: #284b63;
            --accent-glow: rgba(40, 75, 99, 0.15);
            --banner-bg: rgba(40, 75, 99, 0.05);
            --banner-border: rgba(40, 75, 99, 0.12);
            --code-bg: #eef1f4;
            --header-grad: linear-gradient(135deg, #284b63 0%, #1e3547 100%);
            --shadow-sm: 0 2px 8px rgba(0, 0, 0, 0.04);
            --shadow-md: 0 8px 30px rgba(0, 0, 0, 0.06);
          }

          @media (prefers-color-scheme: dark) {
            :root {
              --bg-color: #161618;
              --text-color: #ebebec;
              --text-muted: #a0a0a5;
              --card-bg: rgba(30, 30, 34, 0.7);
              --card-border: rgba(255, 255, 255, 0.06);
              --card-hover-border: #7b97aa;
              --accent-color: #7b97aa;
              --accent-glow: rgba(123, 151, 170, 0.25);
              --banner-bg: rgba(123, 151, 170, 0.08);
              --banner-border: rgba(123, 151, 170, 0.15);
              --code-bg: #1e1e22;
              --header-grad: linear-gradient(135deg, #7b97aa 0%, #526775 100%);
              --shadow-sm: 0 2px 8px rgba(0, 0, 0, 0.2);
              --shadow-md: 0 8px 30px rgba(0, 0, 0, 0.3);
            }
          }

          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            margin: 0;
            padding: 0;
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
          }

          .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 3rem 1.5rem 5rem 1.5rem;
          }

          .banner {
            background: var(--banner-bg);
            border: 1px solid var(--banner-border);
            backdrop-filter: blur(8px);
            -webkit-backdrop-filter: blur(8px);
            border-radius: 16px;
            padding: 1.75rem;
            margin-bottom: 3rem;
            box-shadow: var(--shadow-sm);
            position: relative;
            overflow: hidden;
          }

          .banner::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            width: 5px;
            height: 100%;
            background: var(--header-grad);
          }

          .banner h2 {
            margin: 0 0 0.5rem 0;
            font-size: 1.25rem;
            font-weight: 600;
            color: var(--accent-color);
            display: flex;
            align-items: center;
            gap: 0.5rem;
          }

          .banner p {
            margin: 0 0 1.25rem 0;
            font-size: 0.95rem;
            color: var(--text-muted);
          }

          .copy-box {
            display: flex;
            gap: 0.5rem;
            margin-top: 1rem;
          }

          .copy-input {
            flex-grow: 1;
            background: var(--code-bg);
            border: 1px solid var(--card-border);
            color: var(--text-color);
            padding: 0.75rem 1rem;
            font-family: "IBM Plex Mono", Menlo, Monaco, Consolas, Courier, monospace;
            font-size: 0.85rem;
            border-radius: 8px;
            outline: none;
            transition: border-color 0.2s ease;
          }

          .copy-input:focus {
            border-color: var(--accent-color);
          }

          .btn {
            background: var(--header-grad);
            color: #ffffff !important;
            border: none;
            padding: 0.75rem 1.5rem;
            font-size: 0.9rem;
            font-weight: 600;
            border-radius: 8px;
            cursor: pointer;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
            box-shadow: 0 4px 12px var(--accent-glow);
          }

          .btn:hover {
            transform: translateY(-1px);
            box-shadow: 0 6px 16px var(--accent-glow);
            opacity: 0.95;
          }

          .btn-secondary {
            background: transparent;
            border: 1px solid var(--banner-border);
            color: var(--text-color) !important;
            box-shadow: none;
          }

          .btn-secondary:hover {
            background: var(--banner-bg);
            box-shadow: none;
          }

          header {
            margin-bottom: 3.5rem;
            text-align: left;
          }

          header h1 {
            font-size: 2.5rem;
            margin: 0 0 0.5rem 0;
            font-weight: 800;
            background: var(--header-grad);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            letter-spacing: -0.03em;
          }

          .header-meta {
            color: var(--text-muted);
            font-size: 1.1rem;
            margin: 0 0 1.5rem 0;
          }

          .btn-group {
            display: flex;
            gap: 0.75rem;
          }

          .feed-title {
            font-size: 1.6rem;
            font-weight: 700;
            margin-bottom: 2rem;
            border-bottom: 1px solid var(--card-border);
            padding-bottom: 0.75rem;
            letter-spacing: -0.02em;
          }

          .post-list {
            display: flex;
            flex-direction: column;
            gap: 1.75rem;
          }

          .post-card {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 16px;
            padding: 2rem;
            transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
            box-shadow: var(--shadow-sm);
          }

          .post-card:hover {
            transform: translateY(-2px);
            border-color: var(--card-hover-border);
            box-shadow: var(--shadow-md);
          }

          .post-card h3 {
            margin: 0 0 0.5rem 0;
            font-size: 1.35rem;
            font-weight: 700;
            letter-spacing: -0.01em;
          }

          .post-card h3 a {
            color: var(--text-color);
            text-decoration: none;
            transition: color 0.2s ease;
          }

          .post-card h3 a:hover {
            color: var(--accent-color);
          }

          .post-date {
            font-size: 0.85rem;
            color: var(--text-muted);
            margin-bottom: 1.25rem;
            display: flex;
            align-items: center;
            gap: 0.35rem;
          }

          .post-description {
            font-size: 1rem;
            color: var(--text-muted);
            line-height: 1.65;
          }

          .post-description p {
            margin: 0;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="banner">
            <h2>
              <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="feather feather-rss">
                <path d="M4 11a9 9 0 0 1 9 9"></path>
                <path d="M4 4a16 16 0 0 1 16 16"></path>
                <circle cx="5" cy="19" r="1"></circle>
              </svg>
              RSS Feed Reader Required
            </h2>
            <p>
              This page is an XML Feed designed for newsreaders and feed aggregators (like Feedly, NetNewsWire, or Inoreader). 
              To subscribe, copy the URL below and paste it into your favorite feed reader.
            </p>
            <div class="copy-box">
              <input type="text" id="feed-url" class="copy-input" readonly="readonly" />
              <button id="copy-btn" class="btn">Copy RSS URL</button>
            </div>
          </div>

          <header>
            <h1><xsl:value-of select="/rss/channel/title"/></h1>
            <p class="header-meta"><xsl:value-of select="/rss/channel/description"/></p>
            <div class="btn-group">
              <a class="btn" href="{/rss/channel/link}">Visit Website</a>
            </div>
          </header>

          <main>
            <div class="feed-title">Recent Updates</div>
            <div class="post-list">
              <xsl:for-each select="/rss/channel/item">
                <article class="post-card">
                  <h3>
                    <a href="{link}"><xsl:value-of select="title"/></a>
                  </h3>
                  <div class="post-date">
                    <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                      <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
                      <line x1="16" y1="2" x2="16" y2="6"></line>
                      <line x1="8" y1="2" x2="8" y2="6"></line>
                      <line x1="3" y1="10" x2="21" y2="10"></line>
                    </svg>
                    <xsl:value-of select="pubDate"/>
                  </div>
                  <div class="post-description">
                    <xsl:value-of select="description" disable-output-escaping="yes"/>
                  </div>
                </article>
              </xsl:for-each>
            </div>
          </main>
        </div>

        <script type="text/javascript">
          <![CDATA[
            document.addEventListener('DOMContentLoaded', () => {
              const feedUrlInput = document.getElementById('feed-url');
              if (feedUrlInput) {
                feedUrlInput.value = window.location.href;
              }
              
              const copyBtn = document.getElementById('copy-btn');
              if (copyBtn && feedUrlInput) {
                copyBtn.addEventListener('click', () => {
                  navigator.clipboard.writeText(feedUrlInput.value).then(() => {
                    const originalText = copyBtn.innerText;
                    copyBtn.innerText = 'Copied!';
                    const prevBg = copyBtn.style.background;
                    copyBtn.style.background = '#22c55e';
                    setTimeout(() => {
                      copyBtn.innerText = originalText;
                      copyBtn.style.background = prevBg;
                    }, 2000);
                  });
                });
              }
            });
          ]]>
        </script>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
