# Xcode Project Update Protocol

## ⚠️ CRITICAL: ALWAYS UPDATE XCODE PROJECT WHEN CREATING NEW FILES

**This must be done SYSTEMATICALLY every time new Swift files are created.**

---

## Why This Matters

The project uses both:
1. **Swift Package Manager** (Package.swift) - for command-line builds (`swift build`)
2. **Xcode Project** (Victor.xcodeproj) - for Xcode IDE builds

SPM automatically discovers new files, but **Xcode requires manual project file updates**.

---

## When to Update

**IMMEDIATELY after creating any new Swift file using Write tool.**

Example: If you create `NewView.swift`, you must update `Victor.xcodeproj/project.pbxproj` in the same response.

---

## How to Update (Step-by-Step)

### Step 1: Generate Unique IDs
For each new file, you need 2 unique IDs:
- **Build File ID**: `1000000000000XXX` (increment XXX from last used)
- **File Reference ID**: `2000000000000XXX` (same XXX value)

Example for 4 new files:
- PreviewPanel.swift → `1000000000000014` / `2000000000000014`
- FrontmatterBottomPanel.swift → `1000000000000015` / `2000000000000015`
- EditorPanelView.swift → `1000000000000016` / `2000000000000016`
- FileListView.swift → `1000000000000017` / `2000000000000017`

### Step 2: Add to PBXBuildFile Section
Find `/* End PBXBuildFile section */` and add entries BEFORE it:

```
1000000000000014 /* PreviewPanel.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2000000000000014 /* PreviewPanel.swift */; };
```

### Step 3: Add to PBXFileReference Section
Find `/* End PBXFileReference section */` and add entries BEFORE it:

```
2000000000000014 /* PreviewPanel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PreviewPanel.swift; sourceTree = "<group>"; };
```

### Step 4: Add to Appropriate PBXGroup
Find the correct group (e.g., `5000000000000008 /* MainWindow */`) and add file references to children array:

```
5000000000000008 /* MainWindow */ = {
    isa = PBXGroup;
    children = (
        2000000000000002 /* ContentView.swift */,
        2000000000000014 /* PreviewPanel.swift */,  // <-- NEW
        ...
    );
```

**Group Mapping:**
- `MainWindow` → Views/MainWindow/*.swift
- `Editor` → Views/Editor/*.swift
- `Preview` → Views/Preview/*.swift
- `Models` → Models/*.swift
- `ViewModels` → ViewModels/*.swift
- `Services` → Services/*.swift

### Step 5: Add to PBXSourcesBuildPhase
Find `8000000000000001 /* Sources */` section and add to `files` array:

```
1000000000000014 /* PreviewPanel.swift in Sources */,
```

### Step 6: Verify Build
**ALWAYS verify the Xcode build works:**

```bash
xcodebuild -project Victor.xcodeproj -scheme Victor -configuration Debug clean build
```

Look for `** BUILD SUCCEEDED **` at the end.

---

## Complete Example (4 Files Added)

### Files Created:
1. `Victor/Views/MainWindow/PreviewPanel.swift`
2. `Victor/Views/MainWindow/FrontmatterBottomPanel.swift`
3. `Victor/Views/MainWindow/EditorPanelView.swift`
4. `Victor/Views/MainWindow/FileListView.swift`

### Edit 1: PBXBuildFile Section
```diff
  1000000000000013 /* EditorViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2000000000000013 /* EditorViewModel.swift */; };
+ 1000000000000014 /* PreviewPanel.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2000000000000014 /* PreviewPanel.swift */; };
+ 1000000000000015 /* FrontmatterBottomPanel.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2000000000000015 /* FrontmatterBottomPanel.swift */; };
+ 1000000000000016 /* EditorPanelView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2000000000000016 /* EditorPanelView.swift */; };
+ 1000000000000017 /* FileListView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2000000000000017 /* FileListView.swift */; };
/* End PBXBuildFile section */
```

### Edit 2: PBXFileReference Section
```diff
  2000000000000013 /* EditorViewModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EditorViewModel.swift; sourceTree = "<group>"; };
+ 2000000000000014 /* PreviewPanel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PreviewPanel.swift; sourceTree = "<group>"; };
+ 2000000000000015 /* FrontmatterBottomPanel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FrontmatterBottomPanel.swift; sourceTree = "<group>"; };
+ 2000000000000016 /* EditorPanelView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EditorPanelView.swift; sourceTree = "<group>"; };
+ 2000000000000017 /* FileListView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileListView.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */
```

### Edit 3: MainWindow PBXGroup
```diff
  5000000000000008 /* MainWindow */ = {
      isa = PBXGroup;
      children = (
          2000000000000002 /* ContentView.swift */,
+         2000000000000016 /* EditorPanelView.swift */,
+         2000000000000015 /* FrontmatterBottomPanel.swift */,
+         2000000000000014 /* PreviewPanel.swift */,
          2000000000000003 /* SidebarView.swift */,
+         2000000000000017 /* FileListView.swift */,
      );
```

### Edit 4: Sources Build Phase
```diff
  1000000000000013 /* EditorViewModel.swift in Sources */,
+ 1000000000000014 /* PreviewPanel.swift in Sources */,
+ 1000000000000015 /* FrontmatterBottomPanel.swift in Sources */,
+ 1000000000000016 /* EditorPanelView.swift in Sources */,
+ 1000000000000017 /* FileListView.swift in Sources */,
);
```

---

## Checklist

After creating new Swift files:

- [ ] Determine next available ID numbers (check last `1000000000000XXX` used)
- [ ] Add entries to **PBXBuildFile section**
- [ ] Add entries to **PBXFileReference section**
- [ ] Add files to appropriate **PBXGroup** (MainWindow, Editor, Preview, Models, ViewModels, Services)
- [ ] Add entries to **PBXSourcesBuildPhase**
- [ ] **Verify Xcode build**: `xcodebuild -project Victor.xcodeproj -scheme Victor clean build`
- [ ] Confirm `** BUILD SUCCEEDED **`

---

## Last Session Update (2025-12-23)

**Files Added (Session 1):**
- PreviewPanel.swift (ID: 14)
- FrontmatterBottomPanel.swift (ID: 15)
- EditorPanelView.swift (ID: 16)
- FileListView.swift (ID: 17)

**Files Added (Session 2 - Quick Wins):**
- AppConstants.swift (ID: 18)
- preview-styles.css (ID: 19) - Resource file

**Next available ID: 20**

**Build Status:** ✅ SUCCEEDED
