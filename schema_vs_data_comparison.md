# Schema vs Data Section Comparison for Onetime Secret Migration

## Executive Summary

✅ **Schema sections are ready for Onetime Secret migration**

The test demonstrates that `<schema>` sections provide **direct JSON serialization** without template interpolation, which is exactly what's needed for Vue SPA mount points.

## Key Findings

### 1. Data Flow with Schema Sections

**Backend (Ruby):**
```ruby
view.render('vue_spa_mount',
  ui: { theme: 'dark', locale: 'en' },
  authentication: { authenticated: true, custid: 'cust_12345' },
  user: { email: 'test@example.com', account_since: 1640000000 },
  # ... more props
)
```

**Template (.rue file):**
```xml
<schema lang="js-zod" window="__ONETIME_STATE__">
const schema = z.object({
  ui: z.object({
    theme: z.string(),
    locale: z.string()
  }),
  authentication: z.object({
    authenticated: z.boolean(),
    custid: z.string().nullable()
  }),
  # ... more schema definitions
});
</schema>

<template>
<!DOCTYPE html>
<html>
  <body>
    <div id="app"><router-view></router-view></div>
  </body>
</html>
</template>
```

**Rendered Output:**
```html
<script id="rsfc-data-..." type="application/json" data-window="__ONETIME_STATE__">
{"ui":{"theme":"dark","locale":"en"},"authentication":{"authenticated":true,"custid":"cust_12345"},"user":{"email":"test@example.com","account_since":1640000000},...}
</script>
<script nonce="..." data-hydration-target="__ONETIME_STATE__">
window['__ONETIME_STATE__'] = JSON.parse(dataScript.textContent);
</script>
```

### 2. Critical Differences: Schema vs Data Sections

| Feature | Data Section (deprecated) | Schema Section (current) |
|---------|--------------------------|-------------------------|
| **Backend Props** | Can pass any values, uses interpolation | Must pass fully-resolved values |
| **Template Syntax** | `{"user": "{{user.name}}"}` | Props serialized directly |
| **Interpolation** | Yes - `{{var}}` evaluated | No - props → JSON directly |
| **Type Safety** | No | Yes (via Zod schema) |
| **JSON Output** | After interpolation | Direct serialization |

### 3. What This Means for Onetime Secret

**Current System (data section):**
```ruby
# VuePoint passes pre-serialized JSON
locals = {
  'ui' => UiSerializer.serialize(...).to_json,  # ❌ Already JSON string
  'authentication' => {...}.to_json              # ❌ Already JSON string
}
```

```xml
<data window="__ONETIME_STATE__">
{
  "ui": {{{ui}}},              # ❌ Triple braces for raw output
  "authentication": {{{authentication}}}
}
</data>
```

**New System (schema section):**
```ruby
# VuePoint passes Ruby hashes
locals = {
  'ui' => UiSerializer.serialize(...),  # ✅ Just the hash
  'authentication' => {...}              # ✅ Just the hash
}
```

```xml
<schema lang="js-zod" window="__ONETIME_STATE__">
const schema = z.object({
  ui: z.object({ theme: z.string(), locale: z.string() }),
  authentication: z.object({ authenticated: z.boolean(), custid: z.string().nullable() })
});
</schema>
```

### 4. Implementation Code Path

From `lib/rhales/hydration_data_aggregator.rb:50-90`:

```ruby
def process_schema_section(parser)
  window_attr = parser.schema_window || 'data'

  # CRITICAL: Direct serialization of props (no template interpolation)
  processed_data = @context.props

  # ... merge logic ...

  @merged_data[window_attr] = processed_data
end
```

The key insight: **Schema sections skip the template interpolation step entirely** and serialize `@context.props` directly to JSON.

### 5. Tested Scenarios

✅ Complex nested objects (ui, authentication, user, etc.)
✅ Nil/null values (nullable schema fields)
✅ Boolean values (true/false preserved)
✅ Numbers (integers preserved)
✅ Strings with template-like syntax (not interpolated)
✅ Custom window attribute (`__ONETIME_STATE__`)
✅ CSP nonce integration (`{{app.nonce}}` in template)
✅ Dark mode inline script (before hydration)
✅ Vue SPA mount point (`<div id="app">`)

### 6. Migration Checklist for Onetime Secret

- [ ] Remove `.to_json` calls in VuePoint class
- [ ] Pass Ruby hashes as locals (not JSON strings)
- [ ] Convert `<data>` section to `<schema>` section
- [ ] Remove triple-braces `{{{var}}}` (not needed with schema)
- [ ] Define Zod schema matching serializer structure
- [ ] Test with all 6 serializers (Config, Auth, Domain, I18n, Messages, System)
- [ ] Verify `window.__ONETIME_STATE__` structure is identical
- [ ] Verify Vue.js initializes correctly with new hydration

### 7. Benefits of Schema Sections

1. **Simpler Backend Code**: No need to pre-serialize to JSON
2. **Type Safety**: Zod schema catches mismatches at build time
3. **Validation**: Runtime validation with middleware (optional)
4. **Cleaner Templates**: No template interpolation confusion
5. **JSON Schema Generation**: Can generate TypeScript types
6. **Better Performance**: One serialization pass (not two)

## Example Migration

**Before (current Onetime Secret):**
```ruby
# apps/web/core/views.rb
class VuePoint < BaseView
  def render(template_name)
    @serialized_data = run_serializers(@view_vars, i18n)

    locals = {}
    @serialized_data.each do |key, value|
      locals[key] = value.to_json  # Pre-serialize everything
    end

    super(template_name, locals: locals)
  end
end
```

```xml
<!-- index.html.erb -->
<data window="__ONETIME_STATE__">
{
  "ui": {{{ui}}},
  "authentication": {{{authentication}}},
  "custid": "{{{custid}}}",
  ...
}
</data>
```

**After (with Rhales schema):**
```ruby
# apps/web/core/views.rb
class VuePoint
  def render(template_name)
    @serialized_data = run_serializers(@view_vars, i18n)

    # Pass hashes directly - no .to_json needed
    view = Rhales::View.new(@req)
    view.render(template_name, @serialized_data)
  end
end
```

```xml
<!-- index.rue -->
<schema lang="js-zod" window="__ONETIME_STATE__">
const schema = z.object({
  ui: z.object({
    theme: z.string(),
    locale: z.string()
  }),
  authentication: z.object({
    authenticated: z.boolean(),
    custid: z.string().nullable()
  }),
  // ... define all 40+ fields from serializers
});
</schema>

<template>
<!DOCTYPE html>
<html lang="{{locale}}" class="light">
<head>
  <script nonce="{{app.nonce}}" language="javascript" type="text/javascript">
    // Dark mode script
  </script>
</head>
<body>
  <div id="app"><router-view></router-view></div>
</body>
</html>
</template>
```

## Conclusion

Schema sections are **production-ready** for the Onetime Secret migration. The test demonstrates:

1. Direct JSON serialization without interpolation
2. Correct handling of complex nested structures
3. Proper nil/null value handling
4. CSP nonce integration
5. Custom window variables
6. Vue SPA mount point compatibility

The migration simplifies backend code by eliminating pre-serialization and provides type safety through Zod schemas.

## Next Steps

1. Create full Zod schema definition for all 40+ Onetime Secret fields
2. Refactor VuePoint to pass hashes instead of JSON strings
3. Convert index.html.erb to index.rue with schema section
4. Run integration tests to verify `window.__ONETIME_STATE__` structure
5. Test Vue.js initialization with new hydration format
6. Deploy to staging for validation
