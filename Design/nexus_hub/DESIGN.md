---
name: Nexus Hub
colors:
  surface: '#f8f9ff'
  surface-dim: '#cbdbf5'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff4ff'
  surface-container: '#e5eeff'
  surface-container-high: '#dce9ff'
  surface-container-highest: '#d3e4fe'
  on-surface: '#0b1c30'
  on-surface-variant: '#45464d'
  inverse-surface: '#213145'
  inverse-on-surface: '#eaf1ff'
  outline: '#76777d'
  outline-variant: '#c6c6cd'
  surface-tint: '#565e74'
  primary: '#000000'
  on-primary: '#ffffff'
  primary-container: '#131b2e'
  on-primary-container: '#7c839b'
  inverse-primary: '#bec6e0'
  secondary: '#0058be'
  on-secondary: '#ffffff'
  secondary-container: '#2170e4'
  on-secondary-container: '#fefcff'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#171c1f'
  on-tertiary-container: '#808488'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dae2fd'
  primary-fixed-dim: '#bec6e0'
  on-primary-fixed: '#131b2e'
  on-primary-fixed-variant: '#3f465c'
  secondary-fixed: '#d8e2ff'
  secondary-fixed-dim: '#adc6ff'
  on-secondary-fixed: '#001a42'
  on-secondary-fixed-variant: '#004395'
  tertiary-fixed: '#dfe3e7'
  tertiary-fixed-dim: '#c3c7cb'
  on-tertiary-fixed: '#171c1f'
  on-tertiary-fixed-variant: '#43474b'
  background: '#f8f9ff'
  on-background: '#0b1c30'
  surface-variant: '#d3e4fe'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 30px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.02em
  headline-sm:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.01em
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: -0.01em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.05em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  sidebar_width: 280px
  gutter: 24px
---

## Brand & Style

This design system is built for a "Personal Data & Tools Hub," prioritizing efficiency, clarity, and a high-end utilitarian feel. It draws heavily from **Modern Corporate** and **Minimalist** movements, focusing on functional elegance. 

The aesthetic is characterized by a "sidebar-centric" architecture where navigation is grounded in deep, stable tones, while the workspace remains airy and focused. The emotional response should be one of "organized calm"—providing the user with a sense of mastery over their personal data. Visuals are defined by precise 1px borders, generous internal whitespace, and a sophisticated interplay between slate and neutral surfaces.

## Colors

The palette is anchored by **Deep Navy (Slate 950)**, used for primary navigation and high-contrast UI elements to provide a sense of structure.

- **Primary:** Deep Navy (#0F172A) – Used for the sidebar background, active states, and primary typography.
- **Secondary:** Accent Blue (#3B82F6) – Used sparingly for focus states, primary buttons, and system-level notifications.
- **Surface/Neutral:** A scale of cool grays. The main workspace uses a pure white surface (#FFFFFF) framed by ultra-light gray borders (#E2E8F0).
- **Background:** The app background (behind cards) utilizes a subtle off-white (#F8FAFC) to create a layered depth effect against white cards.

## Typography

The system utilizes **Inter** exclusively to maintain a systematic, technical feel. Typography is configured with tight letter spacing to enhance the "hub" aesthetic, making the interface feel compact and professional.

- **Headlines:** Use semi-bold weights with negative tracking to create a strong visual anchor.
- **Body:** Optimized for legibility with a slightly increased line height (1.5x).
- **Labels:** Small caps or increased tracking are used for category headers (e.g., in the sidebar) to differentiate them from interactive navigation items.

## Layout & Spacing

The design system follows a strict **8px grid** for all margins, paddings, and component dimensions. 

- **Sidebar:** A fixed 280px sidebar on desktop. It uses vertical stacking with 4px internal spacing between nav items.
- **Content Area:** A fluid container that sits within a 24px gutter. For large displays, content is capped at 1440px to prevent excessive line lengths.
- **Grid:** Use a 12-column grid for dashboard views, with 24px gutters between card components.
- **Mobile:** The sidebar collapses into a bottom-sheet or hidden drawer. Margins reduce to 16px.

## Elevation & Depth

This system utilizes a **Tonal Layering** approach combined with **Low-Contrast Outlines**. 

1.  **Level 0 (Background):** Soft gray (#F8FAFC).
2.  **Level 1 (Main Sidebar/Containers):** Solid white or deep navy.
3.  **Level 2 (Cards):** Pure white with a 1px border (#E2E8F0).
4.  **Level 3 (Popovers/Dropdowns):** Pure white with a subtle ambient shadow (0px 4px 12px rgba(0,0,0, 0.05)) to separate it from the workspace.

Avoid heavy shadows. Depth is primarily communicated through border definition and subtle background shifts.

## Shapes

The system uses a **Rounded** language to soften the professional edges and make the tool feel approachable.

- **Navigation Items:** Use `rounded` (8px) for selection states within the sidebar.
- **Cards & Primary Containers:** Use `rounded-xl` or `rounded-2xl` (16px to 24px) to create the "high-end productivity" hub look.
- **Buttons:** Match navigation items with 8px radius.
- **Inputs:** Maintain 8px for consistency.

## Components

### Sidebar Navigation
- **Active State:** Solid Deep Navy (#0F172A) background with White (#FFFFFF) text/icons.
- **Hover State:** Light Gray (#F1F5F9) background for light mode sidebar; subtle opacity shift for dark.
- **Icons:** Thin-stroke (1.5px or 2px) Lucide icons, sized to 18px.

### Cards
- **Structure:** 1px border (#E2E8F0), 24px internal padding, `rounded-2xl` corners.
- **Header:** Integrated headline-sm with an optional icon or action button in the top right.

### Buttons
- **Primary:** Deep Navy background, white text. No shadow, flat finish.
- **Secondary:** White background, 1px gray border, dark text.
- **Ghost:** No background or border, highlights on hover.

### Input Fields
- **Default:** White background, 1px border (#CBD5E1), 12px horizontal padding.
- **Focus:** 1px border changes to Secondary Blue (#3B82F6) with a subtle 2px outer glow (ring).

### Chips/Badges
- Small, uppercase label-sm. Low-saturation background colors (e.g., light blue for "active", light amber for "pending").