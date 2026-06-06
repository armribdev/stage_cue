# Conventions responsive — Stage Cue

Stage Cue doit offrir une expérience pensée **desktop-first** (sidebar, panneaux,
menus contextuels, raccourcis clavier) tout en restant pleinement utilisable sur
téléphone et tablette. Ce document fixe les seuils et les conventions à suivre —
toute nouvelle décision de layout doit s'appuyer dessus plutôt que sur des
`if (width < x)` ad-hoc.

## Deux décisions distinctes, deux mécanismes

Il y a deux questions responsive différentes dans l'app — ne pas les confondre :

1. **"Quelle structure de navigation/layout adopter ?"** → `DeviceClass`
   (`lib/core/utils/layout_utils.dart`), basé sur la **largeur** de la fenêtre.
2. **"Cet écran doit-il s'ouvrir en page ou en modale centrée ?"** →
   `preferModalPresentation` / `openAdaptiveScreen` (`app_modal.dart`), basé sur
   la **plus petite dimension** (`shortestSide >= 600`) — pertinent même en
   orientation paysage sur téléphone.

## Breakpoints — `AppBreakpoints`

| Catégorie | Largeur | Navigation attendue |
|---|---|---|
| `DeviceClass.phone` | `< 840` | Drawer, bottom navigation, plein écran, interactions tactiles (long press, swipe) |
| `DeviceClass.tablet` | `840 – 1199` | Navigation hybride (drawer rétractable ou rail, mélange tactile/pointeur) |
| `DeviceClass.desktop` | `≥ 1200` | Sidebar persistante, panneaux latéraux, menus contextuels, raccourcis clavier, hover |

Ces seuils sont alignés sur les conventions Material/Fluent et cohérents avec le
seuil `600` déjà utilisé pour la décision modale-vs-page.

## Comment trancher selon la plateforme

Utiliser `context.deviceClass` (extension sur `BuildContext`) plutôt que de
comparer `MediaQuery.sizeOf(context).width` directement :

```dart
if (context.deviceClass.isDesktop) {
  // sidebar persistante
}
```

Pour les layouts qui changent structurellement selon l'appareil, utiliser
`AdaptiveLayout` (repli en cascade desktop → tablet → phone si un builder
manque) plutôt qu'un `LayoutBuilder` ad-hoc :

```dart
AdaptiveLayout(
  phone: (context) => _CompactSamplerLayout(...),
  desktop: (context) => _SidebarSamplerLayout(...),
)
```

## Interactions desktop vs mobile

Les interactions "mobile-only" doivent être repensées pour souris/clavier :

| Mobile | Desktop |
|---|---|
| Long press (menu contextuel) | Clic droit / menu contextuel au survol |
| Swipe (révéler une action) | Boutons visibles ou apparaissant au survol (`MouseRegion`/`onHover`) |
| FAB | Action dans une toolbar / barre d'actions |
| Bottom sheet | Panneau latéral ou popover ancré |
| Drawer plein écran | Sidebar persistante |

Sur desktop, prévoir systématiquement : états `hover`/`focus` visibles,
raccourcis clavier pour les actions fréquentes (cf. `Shortcuts`/`Actions` déjà
en place pour Ctrl+Z dans `sampler_screen.dart`), et tooltips sur les icônes
sans libellé.

## Quand documenter un nouveau pattern

Dès qu'un écran introduit une nouvelle variante de layout responsive ou une
nouvelle adaptation d'interaction desktop/mobile, ajouter une ligne ici (et dans
`docs/design_system.md` si un nouveau composant partagé en découle) — pour que
les futures contributions restent cohérentes avec ce qui existe déjà.
