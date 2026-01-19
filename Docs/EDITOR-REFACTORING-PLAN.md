# Editor Refactoring Plan: Code Pattern Extraction

**Status:** In Progress
**Created:** 2026-01-19
**Goal:** Extract 600-700 lines of duplicated code, fix critical HugoConfig bugs, standardize editor patterns

## Executive Summary

This refactoring addresses significant code duplication across 5 editor views and critical inconsistencies in the model layer, particularly HugoConfig's manual change flag management which creates bug risk.

**Estimated Impact:**
- Remove 600-700 lines of duplicated code
- Eliminate critical HugoConfig bug risk (manual flag → computed property)
- Standardize patterns across all editors
- Improve maintainability

## Problem Statement

### Critical Issues

1. **HugoConfig Manual Change Flag** (High Risk)
   - Uses manual `var hasUnsavedChanges: Bool = false`
   - All other models use computed property
   - Risk: Flag can drift out of sync, causing phantom "unsaved changes" or lost data

2. **Missing markAsSaved() Pattern**
   - HugoConfig manually resets flag in SiteViewModel
   - All other models have `markAsSaved()` method
   - Inconsistent API across models

3. **600-700 Lines of Duplication**
   - Toolbar layouts: ~50 lines × 5 editors
   - Save/reload functions: ~30 lines × 5 editors
   - State management: ~5 lines × 5 editors
   - Form/raw toggle: ~20 lines × 3 editors

## Implementation Phases

### Phase 1: Model Layer Standardization (Critical - MUST GO FIRST)

**Objective:** Create consistent model interface, fix HugoConfig critical bug

**Tasks:**
1. Create `EditableFile` protocol
   - Properties: `id`, `url`, `hasUnsavedChanges`, `fileName`
   - Method: `markAsSaved()`
   - Conformance: `Observable`, `Identifiable`, `Hashable`

2. Fix HugoConfig
   - Add stored `originalContent: String`
   - Convert `hasUnsavedChanges` to computed property
   - Add `markAsSaved()` method
   - Add `Identifiable`/`Hashable` conformance
   - Conform to `EditableFile`

3. Update existing models
   - Archetype.swift → conform to `EditableFile`
   - Template.swift → conform to `EditableFile`
   - DataFile.swift → conform to `EditableFile`

4. Update SiteViewModel
   - Replace `config.hasUnsavedChanges = false` with `config.markAsSaved()`

**Files Modified:**
- NEW: `Victor/Protocols/EditableFile.swift`
- `Victor/Models/HugoConfig.swift`
- `Victor/Models/Archetype.swift`
- `Victor/Models/Template.swift`
- `Victor/Models/DataFile.swift`
- `Victor/ViewModels/SiteViewModel.swift`

**Risk:** Low - straightforward standardization
**Time:** 2-3 hours

### Phase 2: View Layer - Extract Common State & Helpers

**Objective:** Extract reusable helpers, use existing components

**Tasks:**
1. Create `EditorState` protocol
   - Properties: `isSaving`, `showSavedIndicator`, `errorMessage`
   - Method: `showSavedIndicatorBriefly()` async

2. Update ArchetypeEditorView to use FileStatusBadgeView
   - Replace lines 81-96 (manual badge code)
   - Use existing `FileStatusBadgeView` component

3. Standardize animation constants
   - Define in `AppConstants.Animation`
   - Update all editors to use constants

**Files Modified:**
- NEW: `Victor/Protocols/EditorState.swift`
- `Victor/Views/ArchetypeEditor/ArchetypeEditorView.swift`
- `Victor/Utilities/AppConstants.swift`
- All 5 editor views (for animation constants)

**Risk:** Very low - minor improvements
**Time:** 1-2 hours

### Phase 3: Extract Save/Reload Logic

**Objective:** Standardize save/reload flow with protocol extension

**Tasks:**
1. Create `EditableEditor` protocol
   - Associated type: `Model: EditableFile`
   - Required properties: `model`, `isSaving`, `showSavedIndicator`, `errorMessage`
   - Required methods: `performSave()`, `performReload()`, `onSaveComplete()`
   - Default implementation: `save()`, `reload()` with error handling

2. Update all editors to conform
   - ArchetypeEditorView
   - TemplateEditorView
   - DataFileEditorView
   - ConfigEditorView
   - TranslationEditorView

**Files Modified:**
- NEW: `Victor/Protocols/EditableEditor.swift`
- All 5 editor views

**Risk:** Medium - protocol with associated types, async patterns
**Time:** 5-6 hours

### Phase 4: Extract Toolbar Components

**Objective:** Create reusable toolbar button components

**Tasks:**
1. Create toolbar button components
   - `EditorSaveButton<Model: EditableFile>`
   - `EditorReloadButton`
   - `EditorExternalEditButton`
   - `EditorRevealInFinderButton`
   - `EditorSavingIndicator`
   - `EditorErrorDisplay`

2. Create standard toolbar layout
   - `EditorToolbar<Model, Leading, Trailing>`
   - Icon + filename + badges + status + custom content + standard buttons

3. Update all editors to use toolbar components
   - Replace manual toolbar code
   - Reduces toolbar code by ~40%

**Files Modified:**
- NEW: `Victor/Views/Components/EditorToolbarButtons.swift`
- NEW: `Victor/Views/Components/EditorToolbar.swift`
- All 5 editor views

**Risk:** Medium - need to handle all variations
**Time:** 4-5 hours

### Phase 5: Form/Raw Toggle Abstraction

**Objective:** Standardize form/raw toggle mechanism

**Tasks:**
1. Create `FormRawToggleable` protocol
   - Required methods: `serializeToRaw()`, `parseFromRaw()`
   - Default implementation: `handleToggle()`, `formRawPicker` view

2. Update applicable editors
   - DataFileEditorView
   - ConfigEditorView
   - TranslationEditorView

**Files Modified:**
- NEW: `Victor/Protocols/FormRawToggleable.swift`
- 3 editor views with form/raw toggle

**Risk:** Medium-High - affects data flow
**Time:** 3-4 hours

## Testing Strategy

### Phase 1 Testing (Critical)
- Unit tests for HugoConfig change detection
- Integration tests for save/markAsSaved flow
- Test all models for EditableFile conformance
- Verify hasUnsavedChanges accuracy

### Phase 2 Testing
- Visual verification of FileStatusBadgeView in archetype editor
- Test animation consistency
- Test showSavedIndicatorBriefly timing

### Phase 3 Testing
- Test save() protocol method for all editors
- Test reload() protocol method for all editors
- Verify error handling in protocol extension
- Test onSaveComplete callbacks

### Phase 4 Testing
- Visual regression tests for all toolbars
- Test button states (enabled/disabled)
- Test keyboard shortcuts
- Test accessibility labels

### Phase 5 Testing
- Test serialization for DataFile, Config, Translation
- Test parse error handling
- Test round-trip (form → raw → form)
- Verify data integrity

### Integration Testing
- Test complete save flow for all file types
- Test hasUnsavedChanges across all models
- Test SiteViewModel aggregation of changes
- End-to-end file editing scenarios

## Risk Mitigation

### High-Risk Changes
1. **HugoConfig refactoring** - Add extensive tests before/after
2. **Protocol-based save logic** - Test async/await patterns thoroughly
3. **Toolbar component extraction** - Visual regression testing

### Rollback Plan
- Keep backup branches for each phase
- Test each phase independently before moving to next
- Maintain backward compatibility during migration

### Testing Checkpoints
- Run full test suite after each phase
- Manual testing of all 5 editor types
- Verify no regressions in existing functionality

## Success Metrics

- ✅ Zero manual hasUnsavedChanges flag management
- ✅ All models conform to EditableFile
- ✅ All editors conform to EditableEditor
- ✅ 600+ lines of duplication removed
- ✅ All tests passing
- ✅ No regressions in editor functionality

## File Structure Summary

### New Protocol Files
- `Victor/Protocols/EditableFile.swift`
- `Victor/Protocols/EditorState.swift`
- `Victor/Protocols/EditableEditor.swift`
- `Victor/Protocols/FormRawToggleable.swift`

### New Component Files
- `Victor/Views/Components/EditorToolbarButtons.swift`
- `Victor/Views/Components/EditorToolbar.swift`

### Modified Model Files
- `Victor/Models/HugoConfig.swift` ⚠️ CRITICAL
- `Victor/Models/Archetype.swift`
- `Victor/Models/Template.swift`
- `Victor/Models/DataFile.swift`

### Modified View Files
- `Victor/Views/ArchetypeEditor/ArchetypeEditorView.swift`
- `Victor/Views/TemplateEditor/TemplateEditorView.swift`
- `Victor/Views/DataEditor/DataFileEditorView.swift`
- `Victor/Views/ConfigEditor/ConfigEditorView.swift`
- `Victor/Views/TranslationEditor/TranslationEditorView.swift`

### Modified ViewModel Files
- `Victor/ViewModels/SiteViewModel.swift`

### Modified Utility Files
- `Victor/Utilities/AppConstants.swift`

## Implementation Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Model Layer | 2-3 hours | None |
| Phase 2: View State | 1-2 hours | Phase 1 |
| Phase 3: Save/Reload | 5-6 hours | Phase 1 |
| Phase 4: Toolbar Components | 4-5 hours | Phase 3 |
| Phase 5: Form/Raw Toggle | 3-4 hours | Phase 3 |
| **Total** | **15-20 hours** | Sequential |

## References

- Original analysis: Plan mode session transcript
- Code review findings: `Docs/CODE-REVIEW-ISSUES.yaml`
- Project instructions: `CLAUDE.md`
