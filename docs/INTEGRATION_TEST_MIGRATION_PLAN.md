# Integration Test Migration Plan

## Overview

The package management system has been successfully migrated from a legacy format (individual package manager fields) to a modern tags-based architecture. However, several integration tests were temporarily skipped during this migration because they depend on APIs and classes that were removed or significantly changed.

This document outlines a comprehensive plan to update these tests for the new tagged architecture.

## Current Status

### ✅ Working Tests
- **Core Package Management Tests** - All 6 functional tests pass
- **Tagging System Tests** - All 33 tests for the new tags architecture pass
- **Main Workflow Tests** - Package analysis, generation, roundtrip validation all working

### ⏸️ Skipped Tests (25 total)
- **Integration Tests** (`test_package_integration.py`) - 4 test classes
- **Custom Install Tests** (`test_custom_install.py`) - 6 test classes

## Migration Plan

### Phase 1: API Compatibility Layer (Estimated: 2-3 days)

Create adapter classes to bridge between old test expectations and new tagged architecture.

#### 1.1 Create Legacy API Adapters
**File:** `tests/adapters/legacy_api.py`

```python
class LegacyPackageFilterAdapter:
    """Adapter to make TaggedPackageFilter compatible with old API."""
    
class LegacyRepologyClientAdapter:
    """Adapter to wrap new CLI functionality for old test expectations."""
    
class LegacyPackageFileGeneratorAdapter:
    """Adapter to make TaggedPackageFileGenerator work with old constructor signatures."""
```

**Dependencies:**
- Import from `package_analysis_cli.py` and `package_generators_tagged.py`
- Map old constructor signatures to new tagged classes
- Provide compatibility methods for changed APIs

#### 1.2 Update Test Imports
**Files to modify:**
- `tests/test_package_integration.py` 
- `tests/test_custom_install.py`

**Changes:**
- Import adapter classes instead of removed modules
- Update class instantiation to use adapters
- Maintain existing test logic while using new backend

### Phase 2: Test Architecture Updates (Estimated: 3-4 days)

Update test structure to work with the new tags-based system while preserving test coverage.

#### 2.1 Package Integration Tests (`test_package_integration.py`)

**TestPackageWorkflowIntegration:**
- ✅ **Keep:** End-to-end workflow validation concept
- 🔄 **Update:** Use `package_analysis_cli.py` for TOML generation
- 🔄 **Update:** Use `TaggedPackageFileGenerator` for file generation
- 🔄 **Update:** Test data to include tags instead of just legacy fields

**TestPackageWorkflowErrorHandling:**
- ✅ **Keep:** Error handling validation concept
- 🔄 **Update:** Error conditions relevant to tagged system
- ➕ **Add:** New error cases (invalid tag queries, malformed tags)

#### 2.2 Custom Install Tests (`test_custom_install.py`)

**Focus Areas:**
- Custom installation file parsing (Customfile format) 
- Platform-specific command resolution
- Integration with tagged package filtering
- gum integration for user prompts

**Strategy:**
- Update to use `EnhancedPlatformDetector` instead of old `PlatformDetector`
- Test custom install integration with tagged package queries
- Validate custom install priority resolution with tags

### Phase 3: Enhanced Test Coverage (Estimated: 2-3 days)

Add new tests specific to the tagged architecture capabilities.

#### 3.1 New Integration Test Categories

**Tag-Based Workflow Tests:**
```python
class TestTaggedWorkflowIntegration:
    def test_tag_query_to_package_generation_workflow(self):
        """Test: tag query → filtered packages → generated files"""
    
    def test_role_based_package_filtering_workflow(self):
        """Test: role specification → appropriate packages → platform files"""
    
    def test_cross_platform_tag_consistency_workflow(self):
        """Test: same tags → consistent packages across platforms"""
```

**Advanced Error Handling Tests:**
```python
class TestTaggedErrorHandling:
    def test_invalid_tag_query_handling(self):
        """Test malformed tag queries fail gracefully"""
    
    def test_missing_tag_namespace_handling(self):
        """Test unrecognized namespaces are handled properly"""
    
    def test_conflicting_tag_combinations(self):
        """Test contradictory tag combinations (e.g., os:macos AND os:linux)"""
```

#### 3.2 Performance and Scalability Tests
```python
class TestTaggedPerformance:
    def test_large_toml_file_processing(self):
        """Test performance with 1000+ packages"""
    
    def test_complex_tag_query_performance(self):
        """Test performance with nested AND/OR/NOT queries"""
```

### Phase 4: Test Data Migration (Estimated: 1-2 days)

Update test fixtures and data to use the new tagged format.

#### 4.1 Test TOML Files
**Files to update:**
- `tests/assets/package_mapping/test_*.toml`

**Changes:**
- Add `tags` fields to all test packages
- Ensure tags align with package characteristics
- Include variety of tag combinations for comprehensive testing

#### 4.2 Mock Data Updates
- Update mock Repology responses to include tag-relevant metadata
- Create mock tagged package data for various scenarios
- Add test cases for tag inheritance and auto-generation

## Implementation Strategy

### Step-by-Step Approach

1. **Start with Adapters** - Create compatibility layer first
2. **Un-skip One Test Class** - Begin with simplest integration test
3. **Fix and Validate** - Ensure that test class passes completely
4. **Repeat Incrementally** - Move to next test class
5. **Add New Tests** - Only after all existing tests are migrated

### Risk Mitigation

- **Incremental Migration** - Fix one test class at a time
- **Parallel Development** - Keep existing functional tests working
- **Rollback Plan** - Maintain skip decorators until replacement tests are verified
- **Documentation** - Update test documentation as changes are made

## Success Criteria

### Completion Metrics
- [ ] All 25 skipped tests are either migrated or replaced
- [ ] Test coverage maintains >= 80% for package management components
- [ ] New tests cover tagged architecture features not tested before
- [ ] No functional regressions in main package management workflows

### Quality Gates
- [ ] All tests pass consistently in CI/CD
- [ ] Test execution time remains reasonable (< 2 minutes for full suite)
- [ ] Test failures provide clear, actionable error messages
- [ ] Integration tests accurately reflect real-world usage patterns

## Timeline Estimate

**Total: 8-12 days**

- Phase 1 (API Adapters): 2-3 days
- Phase 2 (Architecture Updates): 3-4 days  
- Phase 3 (Enhanced Coverage): 2-3 days
- Phase 4 (Test Data): 1-2 days

## Dependencies

### Technical Dependencies
- Working knowledge of the new tagged architecture
- Understanding of the old API contracts from existing tests
- Access to test data and fixtures

### Resource Dependencies
- Development environment with both old and new code for reference
- Ability to run tests in isolation during migration
- Documentation of the tagged architecture design

## Future Considerations

### Maintenance
- Regular review of test coverage as tagged architecture evolves
- Integration with automated dependency updates
- Performance monitoring as test suite grows

### Extensions
- Consider property-based testing for tag combinations
- Integration with packaging system CI/CD workflows
- Cross-platform test execution validation

---

## Quick Start Guide

To begin migration work:

1. **Read the code:**
   ```bash
   # Understand current tagged architecture
   cat lib/tagged_package_filter.py
   cat bin/package_generators_tagged.py
   
   # Review skipped tests
   grep -A 10 "@pytest.mark.skip" tests/test_*.py
   ```

2. **Create adapter foundation:**
   ```bash
   mkdir -p tests/adapters
   touch tests/adapters/__init__.py
   touch tests/adapters/legacy_api.py
   ```

3. **Start with one test:**
   ```bash
   # Pick the simplest failing test and work on it
   pytest tests/test_package_integration.py::TestPackageWorkflowErrorHandling::test_corrupted_toml_file_handling -v
   ```

This migration will significantly improve the robustness and maintainability of the package management test suite while ensuring full compatibility with the new tagged architecture.