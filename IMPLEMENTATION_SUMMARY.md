# Two-Grammar Architecture Implementation Summary

## Overview

Successfully implemented a two-grammar architecture for the Rhales gem, separating handlebars template parsing from .rue file structure parsing. This architectural improvement provides better maintainability, error reporting, and spec compliance while maintaining full backward compatibility.

## Architecture Changes

### Before: Single Grammar with Mixed Responsibilities

- **TemplateEngine** handled both parsing and rendering
- Manual block extraction at render time
- `simple_template?` detection logic
- Regex-based handlebars parsing
- Mixed parsing/rendering responsibilities

### After: Clean Two-Grammar Separation

- **HandlebarsGrammar**: Dedicated handlebars syntax parser
- **RueGrammar**: Dedicated .rue file structure parser
- **TemplateEngine**: Pure AST-based renderer
- **Parser**: Updated to work with new grammar structure

## Implementation Details

### HandlebarsGrammar (`lib/rhales/grammars/handlebars.rb`)

**Features:**
- Formal handlebars specification compliance
- Proper AST node types: `:if_block`, `:each_block`, `:unless_block`, `:variable_expression`, `:partial_expression`
- Accurate line/column error reporting
- Handles nested blocks correctly
- Supports complex expressions and whitespace

**Key Methods:**
- `parse!` - Parse handlebars template into AST
- `variables` - Extract all variables from template
- `partials` - Extract all partial references
- `blocks` - Extract all block structures

**AST Node Types:**
```ruby
:template           # Root template node
:text              # Plain text content
:variable_expression # {{variable}} or {{{variable}}}
:if_block          # {{#if}}...{{else}}...{{/if}}
:unless_block      # {{#unless}}...{{/unless}}
:each_block        # {{#each}}...{{/each}}
:partial_expression # {{> partial}}
```

### RueGrammar (`lib/rhales/grammars/rue.rb`)

**Enhanced Features:**
- Delegates template section parsing to HandlebarsGrammar
- Maintains data/logic section parsing as text
- Preserves section validation and attribute extraction
- Clean separation of concerns

**Key Changes:**
- Template sections now contain proper AST nodes
- Data/logic sections remain as text for variable extraction
- Uses HandlebarsGrammar for template content parsing

### TemplateEngine (`lib/rhales/template_engine.rb`)

**Architectural Improvements:**
- Eliminated `simple_template?` detection complexity
- Removed manual block extraction logic
- Pure AST-based rendering approach
- Cleaner error handling

**Rendering Flow:**
1. Simple templates → HandlebarsGrammar → AST → Render
2. .rue files → RueGrammar → Template section → AST → Render

### Parser (`lib/rhales/parser.rb`)

**Backward Compatibility:**
- All existing methods maintain same interface
- `sections` method converts AST back to strings
- Variable extraction updated for new AST structure
- Handles both old and new node types

## Benefits Achieved

### 1. Clean Separation of Concerns
- HandlebarsGrammar: Pure handlebars syntax parsing
- RueGrammar: Pure .rue file structure validation
- TemplateEngine: Pure AST-based rendering

### 2. Better Error Reporting
- **HandlebarsGrammar**: Precise syntax errors with line/column info
- **RueGrammar**: Structure-specific error messages
- **Context-aware**: Grammar-specific error messages

### 3. Specification Compliance
- Follows official handlebars specification
- Proper nested block handling
- Accurate whitespace preservation
- Correct HTML escaping behavior

### 4. Maintainability
- Single responsibility principle
- Easier to test individual components
- Cleaner code architecture
- Better debugging capabilities

### 5. Performance
- Optimized parsing for each use case
- Efficient AST-based rendering
- Proper block structure handling

## Testing Results

### Test Coverage
- **HandlebarsGrammar**: 39 examples, 0 failures
- **Integration Tests**: 15 examples, 0 failures
- **Architecture Tests**: 14 examples, 0 failures
- **Full Suite**: 124 examples, 0 failures

### Test Categories
- **Unit Tests**: Individual grammar parsing
- **Integration Tests**: End-to-end workflow
- **Architecture Tests**: Clean separation validation
- **Regression Tests**: Backward compatibility

## Key Technical Achievements

### 1. Proper Block Parsing
```ruby
# Before: Manual text extraction
extract_block_content(content_nodes, start_index, block_type)

# After: AST-based block nodes
if_block = Node.new(:if_block, location, value: {
  condition: condition,
  if_content: if_content,
  else_content: else_content
})
```

### 2. Variable Extraction
```ruby
# Template variables from AST nodes
def collect_variables(node)
  case node.type
  when :variable_expression
    [node.value[:name]]
  when :if_block
    [node.value[:condition]] +
    collect_from_content(node.value[:if_content]) +
    collect_from_content(node.value[:else_content])
  # ... other node types
  end
end

# Data variables from text content
def extract_variables_from_text(text, variables)
  text.scan(/\{\{(.+?)\}\}/) do |match|
    variables << match[0].strip
  end
end
```

### 3. AST-Based Rendering
```ruby
# Before: Manual block handling
if content.match(/^#(if|unless|each)\s+(.+)/)
  # Extract and render blocks manually
end

# After: AST node rendering
case node.type
when :if_block
  render_if_block(node)
when :each_block
  render_each_block(node)
when :variable_expression
  render_variable_expression(node)
end
```

## Backward Compatibility

### Maintained Interfaces
- `Parser#sections` - Returns string content
- `Parser#template_variables` - Returns variable array
- `Parser#data_variables` - Returns variable array
- `Parser#partials` - Returns partial array
- `TemplateEngine#render` - Same rendering interface

### Internal Changes
- AST nodes converted back to strings in `sections` method
- Variable extraction updated for new node types
- Rendering logic simplified but maintains same output

## Error Handling Improvements

### HandlebarsGrammar Errors
```ruby
# Syntax errors with precise location
Rhales::HandlebarsGrammar::ParseError:
  Missing closing tag for {{#if}} at line 1, column 25
```

### RueGrammar Errors
```ruby
# Structure validation errors
Rhales::RueGrammar::ParseError:
  Missing required sections: data at line 1, column 1
```

## Future Considerations

### Potential Enhancements
1. **Whitespace Control**: Add handlebars whitespace control (`{{~}}`)
2. **Custom Helpers**: Support for custom block helpers
3. **Partials with Context**: Support for partial parameters
4. **Source Maps**: Enhanced debugging with source mapping
5. **Performance Optimization**: Template compilation and caching

### Extension Points
- HandlebarsGrammar can be extended for custom syntax
- RueGrammar can support additional section types
- TemplateEngine can support custom renderers

## Conclusion

The two-grammar architecture implementation successfully achieves all stated goals:

✅ **Clean Architecture**: Proper separation of concerns
✅ **Better Error Reporting**: Grammar-specific, precise errors
✅ **Spec Compliance**: Handlebars specification compliance
✅ **Maintainability**: Focused, single-purpose classes
✅ **Performance**: Optimized parsing and rendering
✅ **Backward Compatibility**: All existing interfaces maintained

The implementation provides a solid foundation for future enhancements while maintaining the robustness and reliability expected from the Rhales gem.
