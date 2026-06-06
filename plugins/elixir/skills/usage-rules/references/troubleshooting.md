# Usage Rules Troubleshooting

## Package not found in deps/

- Check `.usage-rules/` for previously fetched rules
- If not cached, determine version and offer to fetch
- Check if package is in mix.exs dependencies (for version resolution)
- Verify package name spelling (convert `Phoenix.LiveView` -> `phoenix_live_view`)

## Package doesn't provide usage-rules.md

- This is expected - usage rules are a convention, not all packages have them
- Fallback to hex-docs-search for API documentation
- Suggest checking package README or guides
- Encourage package maintainers to add usage rules

## Fetch failures

**Package fetch fails**:
- Verify package name spelling
- Check network connectivity
- Verify package exists on hex.pm
- Try web search as fallback

**Extraction fails**:
- Package was fetched but doesn't include usage-rules.md
- Clean up temp directory
- Note that package doesn't provide rules

## Cache location issues

**Fetched rules not found on repeat queries**:
- Verify `.usage-rules/` directory exists
- Check that fetch command completed successfully
- May need to re-fetch if directories were deleted
- Ensure temp cleanup didn't remove permanent cache

## Section extraction challenges

**Section too large**:
- Increase `-A` value in Grep to get more content
- Or read complete file and extract programmatically
- Consider showing summary + offering full section

**Multiple relevant sections**:
- Extract multiple sections
- Present them in logical order
- Clearly label each section

**No section matches context**:
- Show "## Understanding [Package]" section as default
- List available sections for user to choose from
- Read complete file if user wants comprehensive overview

## Version mismatches

**Different version in deps/ vs cache**:
- Prefer deps/ version (matches project)
- Note version difference if using cache
- Offer to fetch version matching project dependencies

**Version specified doesn't exist**:
- List available versions from hex.pm
- Prompt user to select valid version
- Fall back to latest if user unsure
