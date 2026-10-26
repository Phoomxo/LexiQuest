# Claude Design Direction · LexiQuest Revision 7

# LexiQuest Revision 7 · Design Director Brief Response

## 1. Art Direction: "Treasure Market"

### Visual Principle
The shop is a **curated market of treasures**, not a transactional grid. Each reward family (themes, wallpapers, decorations) has distinct visual treatment. The design balances playful discovery with clear utility.

### Palette
- **Market accent**: `#FF6B35` (warm coral) for shop-specific actions, prices, and highlights
- **Success green**: `#00D9A3` for owned/equipped states
- **Point currency**: `#FFB800` (amber gold) for balance displays and point icons
- Preserve existing primary/surface colors for consistency with broader app

### Typography
- **Headings**: Sarabun Bold 24sp, left-aligned, 32dp line height
- **Prices**: Sarabun SemiBold 18sp, tabular numerals
- **Body/descriptions**: Sarabun Regular 16sp, 24dp line height
- **Micro labels** (owned/equipped): Sarabun Medium 14sp, all-caps with 0.5sp tracking

### Shapes & Cards
- **Theme cards**: 16dp rounded, 2:1 aspect ratio, full-bleed preview with gradient scrim for legibility
- **Wallpaper cards**: 12dp rounded, 4:3 aspect ratio, subtle elevation shadow
- **Decoration items**: circular 80dp avatars with 4dp border when equipped
- **Price tags**: 20dp rounded pill badges, positioned consistently bottom-right on cards

### Imagery & Iconography
- **Point icon**: custom coin/gem silhouette, not generic star
- **Category icons**: distinct metaphors (paint palette for themes, mountain landscape for wallpapers, crown for decorations)
- **Preview mode**: device frame silhouette showing actual UI placement, not abstract mockup

### Motion Principles
- **Entry**: shop slides up from bottom with 300ms decelerate curve
- **Card selection**: gentle 4dp lift with 200ms scale (1.0 → 1.02)
- **Preview transitions**: crossfade between before/after states, 400ms
- **Purchase success**: single confetti burst from center, 600ms, then auto-dismiss

---

## 2. Screen-by-Screen Specification

### 2.1 ร้านธีม (Shop Entry)
**Hierarchy:**
```
[Top App Bar]
← ร้านธีม                                    [Filter icon] [Info icon]

[Balance Card - full width, 16dp rounded, surface+1]
แต้มคงเหลือ                                         1,240
คุณได้รับจาก: ทำแบบทดสอบ +10 · ภารกิจรายวัน +50

[Category Tabs - 56dp height, fixed]
ธีม (6)    พื้นหลัง (8)    ของตกแต่ง (12)
────

[Scrollable Grid - 2 columns, 16dp gap]
[Theme Preview Card]                    [Theme Preview Card]
[Gradient overlay]                      [Gradient overlay]
ชื่อชุดตกแต่ง                            Standard
                        80 แต้ม                          ใช้งานอยู่

[Theme Preview Card]                    [Theme Preview Card]
...

[Bottom padding: 88dp for FAB clearance]
```

**Focal points:**
- Balance card elevated, not buried
- Active tab underlined 4dp, coral accent
- "ใช้งานอยู่" badge: success green, 24dp rounded, 8dp padding
- Price badge: coral background, white text, bottom-right 12dp margin

### 2.2 รายละเอียดธีม (Theme Detail)
**Hierarchy:**
```
[Top App Bar]
← ชุดตกแต่ง Ocean                              [Share icon]

[Hero Preview - 16:9, full-bleed]
[Ocean theme visual with gentle wave animation]

[Content - 20dp gutters]
ชุดตกแต่ง Ocean
80 แต้ม · 6 ส่วนประกอบ

[Chip Group - wrap]
[พื้นหลัง] [สีปุ่ม] [ไอคอน] [แบบอักษร] [เสียง] [เอฟเฟกต์]

รายละเอียด
ชุดตกแต่งสีน้ำเงินสดใส เหมาะสำหรับการเรียนรู้ที่สงบและมีสมาธิ
รองรับโหมดมืดและขนาดตัวอักษรทุกระดับ

[Expandable Section]
> ดูตัวอย่างบนหน้าจริง

[Bottom Action - fixed, 72dp height, surface+2]
แลกเลย 80 แต้ม
[แต้มคงเหลือหลังแลก: 1,160]
```

**Rules:**
- Hero auto-plays subtle animation (3s loop, no user action required)
- Chips read-only, show what's included
- "ดูตัวอย่างบนหน้าจริง" expands in-place, pushes bottom action down
- Bottom action sticky, always visible, shows resulting balance

### 2.3 ตัวอย่างธีม (Theme Preview)
**Hierarchy:**
```
[Dimmed Backdrop]

[Preview Sheet - bottom sheet, 80% height]
[Drag Handle]

[Toggle Controls - 56dp height, center-aligned]
◯ หน้าหลัก    ● หน้าเรียน    ◯ โปรไฟล์

[Device Frame Preview - fills remaining height]
┌────────────────────────────┐
│ [Realistic phone bezel]     │
│ [Actual Home screen with    │
│  Ocean theme applied]       │
│                              │
│ [Interactive scroll/tap]    │
└────────────────────────────┘

[Bottom Actions - 72dp, split]
[ยกเลิก]                      [แลกธีมนี้]
```

**Rules:**
- Preview sheet dismissible by drag-down or backdrop tap
- Toggle switches preview context without leaving sheet
- Device frame shows 360×760dp safe area, actual UI components
- "แลกธีมนี้" proceeds to confirmation, not immediate purchase

### 2.4 ยืนยันการแลก (Redeem Confirmation)
**Hierarchy:**
```
[Dialog - 328dp width, centered]

แลกชุดตกแต่ง Ocean?

ก่อนแลก                       หลังแลก
1,240 แต้ม      →            1,160 แต้ม

ชุดตกแต่งนี้เป็นเพียงการตกแต่ง
ไม่ส่งผลต่อระดับการเรียนหรือความสามารถ

[Actions - 48dp height]
[ยกเลิก]                      [แลกเลย]
```

**Rules:**
- Before/after balances: tabular numerals, 24sp
- Arrow: 24dp icon, neutral gray
- Cosmetic disclaimer: 14sp, secondary text color, centered
- "แลกเลย" coral accent, "ยกเลิก" text button

### 2.5 แลกสำเร็จ (Purchase Success)
**Hierarchy:**
```
[Dialog - 328dp width, centered]

[Success Icon - 64dp, success green]
✓

แลกสำเร็จ!

คุณได้รับชุดตกแต่ง Ocean แล้ว
แต้มคงเหลือ 1,160

[Actions - stacked, 48dp each]
[ใช้งานเลย]
[ภายหลัง]
```

**Rules:**
- Dialog appears after 600ms confetti animation completes
- "ใช้งานเลย" applies theme immediately, dismisses to Home
- "ภายหลัง" dismisses to Shop, item now shows "เป็นเจ้าของแล้ว"

### 2.6 จัดการธีม (Manage Owned Themes)
**Hierarchy:**
```
[Top App Bar]
← ธีมของฉัน                                   [Search icon]

[Active Theme Card - elevated, full-width]
กำลังใช้
[Ocean preview]
ชุดตกแต่ง Ocean

[Section Header - 20dp top margin]
ธีมที่เป็นเจ้าของ (3)

[Grid - 2 columns]
[Standard preview]              [Focus preview]
Standard                         Focus
✓ ใช้งานอยู่                     [เปลี่ยนธีม]

[Empty State if 0 owned]
คุณยังไม่มีธีมเพิ่มเติม
[ไปที่ร้านธีม]
```

**Rules:**
- Active theme card: 8dp elevation, success green accent
- Owned themes show "เปลี่ยนธีม" button, not price
- Tapping owned theme opens detail → "ใช้ธีมนี้" replaces "แลกเลย"

### 2.7 Error States

**แต้มไม่เพียงพอ:**
```
[Snackbar - bottom, 56dp height]
แต้มไม่เพียงพอ · ต้องการอีก 40 แต้ม    [ดูวิธีรับแต้ม]
```

**รายการหมดอายุ:**
```
[Dialog]
รายการนี้หมดอายุแล้ว
กรุณารีเฟรชรายการร้านค้า

[ปิด]  [รีเฟรชเลย]
```

**ออฟไลน์:**
```
[Banner - top, 48dp, warning color]
คุณเป็นเจ้าของรายการนี้แล้ว แต่ต้องการอินเทอร์เน็ตเพื่อดาวน์โหลด
```

---

## 3. Prototype Route Graph & Navigation Rules

### Route Graph
```
Home ──────────────┐
Profile ────────┐  │
AllMenus ───┐   │  │
Progress/Rewards│  │  │
Appearance ─┘   │  │  │
                ↓  ↓  ↓  ↓
            ร้านธีม (Shop Entry)
                │
        ┌───────┼───────┐
        ↓       ↓       ↓
    [Theme] [Wallpaper] [Decoration]
      Tab     Tab         Tab
        │
        ↓
    รายละเอียดธีม (Detail)
        │
        ├──→ ตัวอย่างธีม (Preview Sheet)
        │       │
        │       └──→ ยืนยันการแลก (Dialog)
        │               │
        │               └──→ แลกสำเร็จ (Dialog)
        │                       │
        │                       ├──→ Home (apply now)
        │                       └──→ Shop (later)
        │
        └──→ จัดการธีม (if owned)
                │
                └──→ รายละเอียดธีม (owned item)
```

### Five Critical Navigation Rules

1. **Shop Entry Multi-Access:**
   - Home: "ร้านธีม" card in quick actions row (4-card horizontal scroll)
   - Profile: "ตกแต่งโปรไฟล์" button opens Shop directly on Decoration tab
   - AllMenus: "ร้านธีม และของรางวัล" entry
   - Progress: "ใช้แต้มของคุณ" link below balance chart
   - Appearance: "เปลี่ยนธีม" opens Shop on Theme tab

2. **Back Navigation Preservation:**
   - Shop → Detail → Back = Shop (same tab, scroll position preserved)
   - Detail → Preview Sheet → Back = Detail (sheet dismissed, not Shop)
   - Confirmation Dialog → Back = Detail (cancel purchase)
   - Success Dialog → Back = Shop (after brief delay to prevent accidental skip)

3. **Focus Path for Owned Items:**
   - Shop shows both unowned (price) and owned (checkmark) items in same grid
   - Owned item → Detail shows "ใช้ธีมนี้" or "ใช้งานอยู่" instead of price
   - "จัดการธีม" accessible via Shop overflow menu or Profile/Appearance
   - Manage screen is separate route, not filter on main Shop

4. **Preview Sheet Lifecycle:**
   - Preview is a persistent bottom sheet, not full-screen activity
   - Dismissed by: drag down, backdrop tap, explicit "ยกเลิก", or proceeding to confirmation
   - Does NOT dismiss on: toggle between Home/Learning/Profile previews
   - Survives orientation change and IME open

5. **Post-Purchase Flow:**
   - Success → "ใช้งานเลย" = apply + navigate Home (theme visible immediately)
   - Success → "ภายหลัง" = dismiss to Shop, item shows "เป็นเจ้าของแล้ว", no auto-apply
   - If offline after purchase, show banner on next Shop entry, allow retry download
   - Idempotent: tapping owned item never re-charges points

---

## 4. Revision 6 Concrete Fixes

### Fix 1: Inconsistent Centering
**Problem:** Balance displays, prices, and CTAs use mixed left/center alignment.

**Solution:**
- **Left-align:** all headings ("ร้านธีม", "รายละเอียดธีม"), explanatory text ("คุณได้รับจาก..."), section labels
- **Center-align:** balance numerals in dedicated card, preview controls, single-action CTAs ("แลกเลย 80 แต้ม"), success dialogs
- **Right-align:** price badges on cards (consistently 12dp from bottom-right corner)

### Fix 2: Balance Card Buried
**Problem:** Current balance shown as small header text, easy to miss.

**Solution:**
- Elevate to dedicated card, full-width, 16dp rounded, 16dp padding
- Two-line layout: "แต้มคงเหลือ" (14sp secondary) + "1,240" (32sp primary, tabular)
- Expandable details: "คุณได้รับจาก: ..." as secondary line, +/- chevron to show earning history

### Fix 3: Shop Entry Discoverability
**Problem:** No direct path from Home; users must go Profile → Appearance → [find shop somewhere].

**Solution:**
- Add "ร้านธีม" card to Home quick actions (between "ความคืบหน้า" and "การตั้งค่า")
- Card shows: icon, "ร้านธีม", "ดูธีมใหม่ 2 ชุด" if new items, coral accent
- Profile "ตกแต่งโปรไฟล์" button opens Shop on Decoration tab (not Appearance settings)
- AllMenus gains "ร้านธีม และของรางวัล" entry with coin icon

### Fix 4: Spacing Rhythm Breaks
**Problem:** Inconsistent gaps between sections (12dp, 16dp, 20dp, 24dp mixed).

**Solution:**
- **8dp rhythm:** internal card padding, chip gaps, list item spacing
- **16dp rhythm:** card-to-card gaps in grids, section header top margin
- **20dp rhythm:** screen edge gutters (phone), paragraph spacing
- **24dp rhythm:** major section breaks (balance card → tabs → grid)

### Fix 5: Menu Focus Paths
**Problem:** "จัดการธีม" not surfaced; users cannot find owned items after purchase.

**Solution:**
- Shop overflow menu (⋮) gains two entries: "ธีมของฉัน" and "วิธีรับแต้ม"
- Profile card shows active theme name + "เปลี่ยน" text button (opens Manage screen)
- Appearance settings gains "ธีมและพื้นหลัง" section with current selections, tap to Manage

---

## 5. P0/P1/P2 Critique Rubric

### P0: Functional Blocking Issues
- [ ] All 5 entry paths (Home, Profile, AllMenus, Progress, Appearance) route to Shop correctly
- [ ] Price badges visible and consistently positioned on all unowned items
- [ ] Balance card shows current points and updates after purchase
- [ ] Preview sheet shows realistic device frame with actual UI components, not placeholder
- [ ] Confirmation dialog displays before/after balance and cosmetic disclaimer
- [ ] Success dialog offers "ใช้งานเลย" and "ภายหลัง" actions
- [ ] Owned items show "เป็นเจ้าของแล้ว" or "ใช้งานอยู่", never price
- [ ] Back navigation from Preview sheet returns to Detail, not Shop
- [ ] Error states (insufficient points, offline, stale) display appropriate messaging

### P1: Usability & Polish
- [ ] Balance card expandable details reveal earning sources (quiz, daily, weekly, milestone)
- [ ] Theme/Wallpaper/Decoration tabs use distinct card aspect ratios (2:1, 4:3, 1:1)
- [ ] Active theme card elevated with 8dp shadow and success green accent
- [ ] Preview toggle (Home/Learning/Profile) animates crossfade, not abrupt cut
- [ ] Price badges use coral background, white text, 20dp rounded, tabular numerals
- [ ] Typography follows Sarabun hierarchy (Bold 24sp headings, Regular 16sp body)
- [ ] 48dp minimum touch targets on all interactive elements
- [ ] Spacing adheres to 8dp rhythm (no 5dp, 13dp, or arbitrary gaps)
- [ ] "จัดการธีม" accessible from Shop overflow menu and Profile card

### P2: Refinement & Delight
- [ ] Shop entry animates slide-up from bottom with 300ms decelerate
- [ ] Card selection shows subtle 4dp lift with 1.02 scale
- [ ] Confetti animation plays on purchase success (single burst, 600ms)
- [ ] Hero preview auto-plays gentle animation (3s loop, 20% opacity overlay)
- [ ] Category icons use distinct metaphors (palette, landscape, crown)
- [ ] Custom coin/gem icon for points, not generic star
- [ ] Balance numerals use tabular font variant for alignment
- [ ] Empty state in Manage screen shows friendly illustration + "ไปที่ร้านธีม" CTA
- [ ] Dark theme variant tested for all screens (coral accent remains legible)

---

**Implementation Directive for Codex:**

This is your single source of truth. Build Revision 7 with:
- Exact Thai labels as specified (do not translate or paraphrase)
- 20dp gutters, 8dp rhythm, 48dp touch targets
- Coral accent (#FF6B35) for shop actions, amber gold (#FFB800) for points, success green (#00D9A3) for owned states
- Route graph as drawn, with 5 navigation rules enforced
- Revision 6 fixes applied to affected screens before building new ones

Run P0 checks before handoff. Flag any P1/P2 items that conflict with Figma's Auto Layout or component constraints.