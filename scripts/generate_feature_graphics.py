import os
import sys
import io
import base64
import subprocess
from PIL import Image

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

def to_b64_file(rel_path):
    full_path = os.path.join(REPO_ROOT, rel_path)
    with open(full_path, 'rb') as f:
        return base64.b64encode(f.read()).decode('utf-8')

def pil_to_b64(pil_img):
    buf = io.BytesIO()
    pil_img.save(buf, format='PNG')
    return base64.b64encode(buf.getvalue()).decode('utf-8')

# Preprocess and clean screenshots
# In raw_dash (1080 x 2340):
# Crop out green 12px edge, status bar (top 110px) and bottom nav bar padding
raw_dash = Image.open(os.path.join(REPO_ROOT, 'docs/TourSplit_dashboard.png'))
clean_dash = raw_dash.crop((12, 110, 1068, 2275))
dashboard_b64 = pil_to_b64(clean_dash)

# In raw_math (1080 x 2340):
# Crop to show Add Expense clearly without clipping
raw_math = Image.open(os.path.join(REPO_ROOT, 'docs/TourSplit_math_preview.png'))
clean_math = raw_math.crop((12, 125, 1068, 2040))
math_b64 = pil_to_b64(clean_math)

app_icon_b64 = to_b64_file('assets/brand/app_icon.png')
font_bold_b64 = to_b64_file('assets/fonts/Outfit-Bold.ttf')
font_semibold_b64 = to_b64_file('assets/fonts/Outfit-SemiBold.ttf')
font_medium_b64 = to_b64_file('assets/fonts/Outfit-Medium.ttf')
font_regular_b64 = to_b64_file('assets/fonts/Outfit-Regular.ttf')

html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
@font-face {{
  font-family: 'Outfit';
  font-weight: 400;
  src: url('data:font/truetype;charset=utf-8;base64,{font_regular_b64}') format('truetype');
}}
@font-face {{
  font-family: 'Outfit';
  font-weight: 500;
  src: url('data:font/truetype;charset=utf-8;base64,{font_medium_b64}') format('truetype');
}}
@font-face {{
  font-family: 'Outfit';
  font-weight: 600;
  src: url('data:font/truetype;charset=utf-8;base64,{font_semibold_b64}') format('truetype');
}}
@font-face {{
  font-family: 'Outfit';
  font-weight: 700;
  src: url('data:font/truetype;charset=utf-8;base64,{font_bold_b64}') format('truetype');
}}

* {{
  box-sizing: border-box;
  margin: 0;
  padding: 0;
  -webkit-font-smoothing: antialiased;
}}

body {{
  width: 1024px;
  height: 500px;
  background-color: #030707;
  color: #FFFFFF;
  font-family: 'Outfit', sans-serif;
  overflow: hidden;
  position: relative;
}}

/* Ambient dark background with subtle teal aura */
.bg-grid {{
  position: absolute;
  top: 0;
  left: 0;
  width: 1024px;
  height: 500px;
  background-image: 
    linear-gradient(rgba(45, 212, 191, 0.045) 1px, transparent 1px),
    linear-gradient(90deg, rgba(45, 212, 191, 0.045) 1px, transparent 1px);
  background-size: 32px 32px;
  background-position: -1px -1px;
  pointer-events: none;
}}

.radial-glow-devices {{
  position: absolute;
  top: -20px;
  right: -50px;
  width: 680px;
  height: 540px;
  background: radial-gradient(circle at 60% 50%, rgba(0, 137, 123, 0.38) 0%, rgba(13, 148, 136, 0.14) 45%, rgba(0,0,0,0) 74%);
  pointer-events: none;
}}

.radial-glow-logo {{
  position: absolute;
  top: -60px;
  left: -40px;
  width: 440px;
  height: 320px;
  background: radial-gradient(circle at 35% 35%, rgba(0, 137, 123, 0.28) 0%, rgba(0,0,0,0) 65%);
  pointer-events: none;
}}

/* Left Column Content */
.left-col {{
  position: absolute;
  top: 24px;
  left: 44px;
  width: 450px;
  display: flex;
  flex-direction: column;
  z-index: 10;
}}

.tag-badge {{
  display: inline-flex;
  align-items: center;
  gap: 7px;
  background: linear-gradient(135deg, rgba(0, 137, 123, 0.4) 0%, rgba(13, 148, 136, 0.2) 100%);
  border: 1px solid rgba(45, 212, 191, 0.45);
  border-radius: 20px;
  padding: 4px 13px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.9px;
  text-transform: uppercase;
  color: #2DD4BF;
  width: fit-content;
  box-shadow: 0 2px 10px rgba(0, 137, 123, 0.3);
}}

.tag-dot {{
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background-color: #2DD4BF;
  box-shadow: 0 0 8px #2DD4BF;
}}

.brand-row {{
  display: flex;
  align-items: center;
  gap: 14px;
  margin-top: 10px;
}}

.app-icon-wrap {{
  position: relative;
  width: 50px;
  height: 50px;
}}

.app-icon {{
  width: 50px;
  height: 50px;
  border-radius: 13px;
  border: 1px solid rgba(255, 255, 255, 0.25);
  box-shadow: 0 8px 24px rgba(0, 137, 123, 0.6);
  display: block;
}}

.brand-title {{
  font-size: 42px;
  font-weight: 700;
  letter-spacing: -0.6px;
  color: #FFFFFF;
  line-height: 1;
}}

.version-pill {{
  background: linear-gradient(135deg, #00897B 0%, #0D9488 100%);
  color: #FFFFFF;
  font-size: 13px;
  font-weight: 700;
  padding: 3px 10px;
  border-radius: 6px;
  letter-spacing: 0.4px;
  box-shadow: 0 2px 10px rgba(0, 137, 123, 0.5);
  border: 1px solid rgba(45, 212, 191, 0.4);
}}

.tagline {{
  font-size: 15px;
  font-weight: 500;
  color: #94A3B8;
  margin-top: 7px;
  margin-bottom: 14px;
}}

/* Feature Cards Stack */
.features-container {{
  display: flex;
  flex-direction: column;
  gap: 8px;
}}

.feature-item {{
  display: flex;
  align-items: center;
  gap: 12px;
  background: linear-gradient(90deg, rgba(255, 255, 255, 0.045) 0%, rgba(255, 255, 255, 0.015) 100%);
  border: 1px solid rgba(255, 255, 255, 0.09);
  border-radius: 11px;
  padding: 7px 12px;
  backdrop-filter: blur(8px);
}}

.feature-icon-box {{
  width: 33px;
  height: 33px;
  border-radius: 8px;
  background: linear-gradient(135deg, rgba(0, 137, 123, 0.4) 0%, rgba(13, 148, 136, 0.2) 100%);
  border: 1px solid rgba(45, 212, 191, 0.4);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  box-shadow: 0 2px 8px rgba(0, 137, 123, 0.25);
}}

.feature-icon-box svg {{
  width: 17px;
  height: 17px;
  stroke: #2DD4BF;
  fill: none;
}}

.feature-text {{
  display: flex;
  flex-direction: column;
  gap: 1.5px;
}}

.feature-title {{
  font-size: 13.5px;
  font-weight: 600;
  color: #F8FAFC;
  line-height: 1.2;
}}

.feature-desc {{
  font-size: 11px;
  font-weight: 400;
  color: #94A3B8;
  line-height: 1.2;
}}

/* Bottom Trust Badges */
.bottom-badges {{
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 15px;
}}

.trust-badge {{
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: rgba(255, 255, 255, 0.035);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
  padding: 5px 11px;
  font-size: 11px;
  font-weight: 600;
  color: #CBD5E1;
}}

.trust-badge.highlight {{
  background: rgba(0, 137, 123, 0.18);
  border-color: rgba(45, 212, 191, 0.4);
  color: #2DD4BF;
}}

/* RIGHT COLUMN: EXPANDED PHONE SHOWCASE */
.devices-container {{
  position: absolute;
  top: 0;
  right: 0;
  width: 550px;
  height: 500px;
  z-index: 5;
}}

/* Back Device: Math Calculator */
.device-back {{
  position: absolute;
  left: 20px;
  top: 36px;
  width: 250px;
  height: 480px;
  background: #000000;
  border-radius: 30px;
  border: 3.5px solid #1E293B;
  box-shadow: 
    0 20px 50px rgba(0, 0, 0, 0.9),
    0 0 30px rgba(0, 137, 123, 0.25);
  overflow: hidden;
  z-index: 2;
  transform: perspective(1000px) rotateY(-5deg) rotateZ(1deg);
}}

.device-back .screen-wrap {{
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
  background: #000000;
}}

.device-back img {{
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: top center;
  display: block;
}}

/* Front Device: Dashboard & Live Ledger */
.device-front {{
  position: absolute;
  left: 230px;
  top: 14px;
  width: 285px;
  height: 520px;
  background: #000000;
  border-radius: 34px;
  border: 4px solid #334155;
  box-shadow: 
    0 26px 70px rgba(0, 0, 0, 0.98), 
    0 0 45px rgba(0, 137, 123, 0.4),
    inset 0 0 0 1px rgba(255, 255, 255, 0.2);
  overflow: hidden;
  z-index: 8;
}}

.device-front .screen-wrap {{
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
  background: #000000;
}}

.device-front img {{
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: top center;
  display: block;
}}

/* Modern Punch Hole Camera */
.punch-hole {{
  position: absolute;
  top: 8px;
  left: 50%;
  transform: translateX(-50%);
  width: 10px;
  height: 10px;
  background: #000;
  border: 1.5px solid #1e293b;
  border-radius: 50%;
  z-index: 15;
  box-shadow: inset 0 0 2px rgba(255,255,255,0.2);
}}

/* Floating Highlight Callouts */
.floating-callout-pay {{
  position: absolute;
  left: 0px;
  bottom: 80px;
  background: linear-gradient(135deg, rgba(4, 16, 18, 0.95) 0%, rgba(8, 28, 30, 0.95) 100%);
  border: 1.5px solid #2DD4BF;
  box-shadow: 0 12px 28px rgba(0, 0, 0, 0.9), 0 0 24px rgba(45, 212, 191, 0.45);
  border-radius: 14px;
  padding: 8px 14px;
  display: flex;
  align-items: center;
  gap: 10px;
  z-index: 25;
  backdrop-filter: blur(14px);
}}

.floating-callout-pay .callout-icon {{
  color: #F59E0B;
  font-size: 18px;
}}

.floating-callout-pay .callout-title {{
  font-size: 12.5px;
  font-weight: 700;
  color: #FFFFFF;
}}

.floating-callout-pay .callout-subtitle {{
  font-size: 10px;
  font-weight: 500;
  color: #2DD4BF;
}}

.floating-callout-chat {{
  position: absolute;
  left: 5px;
  top: 14px;
  background: linear-gradient(135deg, rgba(4, 16, 18, 0.95) 0%, rgba(8, 28, 30, 0.95) 100%);
  border: 1.5px solid rgba(45, 212, 191, 0.65);
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.9), 0 0 20px rgba(45, 212, 191, 0.35);
  border-radius: 12px;
  padding: 6px 13px;
  display: flex;
  align-items: center;
  gap: 8px;
  z-index: 25;
  backdrop-filter: blur(12px);
}}

.floating-callout-chat .callout-text {{
  font-size: 11px;
  font-weight: 700;
  color: #2DD4BF;
  display: flex;
  align-items: center;
  gap: 6px;
}}

</style>
</head>
<body>

<div class="bg-grid"></div>
<div class="radial-glow-logo"></div>
<div class="radial-glow-devices"></div>

<!-- LEFT COLUMN -->
<div class="left-col">
  <div class="tag-badge">
    <div class="tag-dot"></div>
    Tour & Group Expenses
  </div>

  <div class="brand-row">
    <div class="app-icon-wrap">
      <img class="app-icon" src="data:image/png;base64,{app_icon_b64}" alt="Logo" />
    </div>
    <span class="brand-title">TourSplit</span>
    <span class="version-pill">v1.5</span>
  </div>

  <div class="tagline">Split costs effortlessly, keep memories.</div>

  <div class="features-container">
    <!-- Feature 1: Math Calculator -->
    <div class="feature-item">
      <div class="feature-icon-box">
        <svg viewBox="0 0 24 24" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="4" y="2" width="16" height="20" rx="2"></rect>
          <line x1="8" y1="6" x2="16" y2="6"></line>
          <line x1="16" y1="14" x2="16" y2="18"></line>
          <path d="M16 10h.01"></path>
          <path d="M12 10h.01"></path>
          <path d="M8 10h.01"></path>
          <path d="M12 14h.01"></path>
          <path d="M8 14h.01"></path>
          <path d="M12 18h.01"></path>
          <path d="M8 18h.01"></path>
        </svg>
      </div>
      <div class="feature-text">
        <div class="feature-title">In-App Smart Math Calculator</div>
        <div class="feature-desc">Evaluate expressions (500*2)+350 live directly in amount field</div>
      </div>
    </div>

    <!-- Feature 2: P2P Mesh & Cloud Chat -->
    <div class="feature-item">
      <div class="feature-icon-box">
        <svg viewBox="0 0 24 24" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"></path>
        </svg>
      </div>
      <div class="feature-text">
        <div class="feature-title">P2P Offline & Cloud Tour Chat</div>
        <div class="feature-desc">Coordinate via Bluetooth mesh or cloud sync with live reactions</div>
      </div>
    </div>

    <!-- Feature 3: Live Trip Summaries & Attribution -->
    <div class="feature-item">
      <div class="feature-icon-box">
        <svg viewBox="0 0 24 24" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
          <line x1="18" y1="20" x2="18" y2="10"></line>
          <line x1="12" y1="20" x2="12" y2="4"></line>
          <line x1="6" y1="20" x2="6" y2="14"></line>
        </svg>
      </div>
      <div class="feature-text">
        <div class="feature-title">Live Trip Summaries & Ledger</div>
        <div class="feature-desc">Total & your spending, Sheet/Cards views & contributor attribution</div>
      </div>
    </div>

    <!-- Feature 4: 1-Tap Payout Accounts -->
    <div class="feature-item">
      <div class="feature-icon-box">
        <svg viewBox="0 0 24 24" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="1" y="4" width="22" height="16" rx="2" ry="2"></rect>
          <line x1="1" y1="10" x2="23" y2="10"></line>
        </svg>
      </div>
      <div class="feature-text">
        <div class="feature-title">1-Tap Payout Accounts & Settlements</div>
        <div class="feature-desc">Quick-copy bKash, Nagad & Bank with haptics & minimal transfers</div>
      </div>
    </div>
  </div>

  <div class="bottom-badges">
    <div class="trust-badge highlight">
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="20 6 9 17 4 12"></polyline>
      </svg>
      100% Free
    </div>
    <div class="trust-badge highlight">
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path>
      </svg>
      Ad-Free & Private
    </div>
    <div class="trust-badge">
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M5 12.55a11 11 0 0 1 14.08 0"></path>
        <path d="M1.42 9a16 16 0 0 1 21.16 0"></path>
        <path d="M8.53 16.11a6 6 0 0 1 6.95 0"></path>
        <line x1="12" y1="20" x2="12.01" y2="20"></line>
      </svg>
      Pure Offline Mode
    </div>
  </div>
</div>

<!-- RIGHT COLUMN: EXPANDED PHONE SHOWCASE -->
<div class="devices-container">
  <!-- Back Device: Math Calculator -->
  <div class="device-back">
    <div class="punch-hole" style="top: 7px; width: 8px; height: 8px;"></div>
    <div class="screen-wrap">
      <img src="data:image/png;base64,{math_b64}" alt="Math Preview" />
    </div>
  </div>

  <!-- Front Device: Dashboard & Ledger -->
  <div class="device-front">
    <div class="punch-hole"></div>
    <div class="screen-wrap">
      <img src="data:image/png;base64,{dashboard_b64}" alt="Dashboard" />
    </div>
  </div>

  <!-- Floating Callouts -->
  <div class="floating-callout-pay">
    <div class="callout-icon">⚡</div>
    <div>
      <div class="callout-title">1-Tap Quick Pay</div>
      <div class="callout-subtitle">Instant Haptic Feedback</div>
    </div>
  </div>

  <div class="floating-callout-chat">
    <div class="callout-text">
      <span>💬</span>
      <span>P2P Mesh & Cloud Sync</span>
    </div>
  </div>
</div>

</body>
</html>
"""

temp_html = os.path.join(REPO_ROOT, 'temp_feature_graphic.html')
with open(temp_html, 'w') as f:
    f.write(html_content)

out_png_2x = os.path.join(REPO_ROOT, 'temp_render_2x.png')
cmd = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '--headless=new',
    '--screenshot=' + out_png_2x,
    '--window-size=1024,500',
    '--device-scale-factor=2',
    '--hide-scrollbars',
    '--default-background-color=00000000',
    temp_html
]
subprocess.run(cmd, check=True)

im = Image.open(out_png_2x)
im_rgb = im.convert('RGB')
im_1024 = im_rgb.resize((1024, 500), Image.Resampling.LANCZOS)

# Save to destination files
im_1024.save(os.path.join(REPO_ROOT, 'play_store_feature_graphic.png'), 'PNG', optimize=True)
im_1024.save(os.path.join(REPO_ROOT, 'play_store_feature_graphic.jpg'), 'JPEG', quality=95)
im_1024.save(os.path.join(REPO_ROOT, 'feature_graphic.png'), 'PNG', optimize=True)
im_1024.save(os.path.join(REPO_ROOT, 'feature_graphic.jpg'), 'JPEG', quality=95)
im_1024.save(os.path.join(REPO_ROOT, 'docs/TourSplit_feature_graphic.png'), 'PNG', optimize=True)
fastlane_path = os.path.join(REPO_ROOT, 'android/app/src/main/fastlane/metadata/android/en-US/images/featureGraphic.png')
if os.path.exists(os.path.dirname(fastlane_path)):
    im_1024.save(fastlane_path, 'PNG', optimize=True)

# Cleanup temp files
if os.path.exists(temp_html):
    os.remove(temp_html)
if os.path.exists(out_png_2x):
    os.remove(out_png_2x)

print('Feature graphics cleanly generated!')
