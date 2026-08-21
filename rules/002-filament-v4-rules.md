# Filament v4 — Coding Agent Rules

> Drop this into `.claude/rules/filament-v4.md`, `AGENTS.md`, `.cursor/rules/`, or a `CLAUDE.md` import.
> Scope: Laravel + `filament/filament ^4.0`. **Do not apply these rules to a v3 or v5 codebase.**

---

## 0. Version guard (run before writing any code)

```bash
composer show filament/filament | grep versions   # must be 4.x
php artisan about | grep -i filament
```

- If the project is on **v3** → STOP and ask. v3 and v4 APIs are incompatible.
- If the project is on **v5** → STOP and ask. v5 renames/moves more APIs (Livewire v4).
- Canonical reference: `https://filamentphp.com/docs/4.x/llms.txt` (index) — fetch the specific page before guessing an API.
- **NEVER** invent method names. If unsure whether a method exists in v4, grep `vendor/filament/**/src` first.

**Requirements:** PHP 8.2+, Laravel 11.28+, Tailwind CSS 4.1+ (only if a custom theme exists). `doctrine/dbal` is no longer required by Filament.

---

## 1. Non-negotiable rules

1. **NEVER use v3 APIs.** No `Filament\Forms\Form`, no `Filament\Infolists\Infolist`, no `Filament\Tables\Actions\*`, no `->actions()` / `->bulkActions()` on tables.
2. **Always scaffold with the official generators** instead of hand-writing boilerplate:
   `make:filament-resource`, `make:filament-page`, `make:filament-widget`, `make:filament-relation-manager`, `make:filament-schema`, `make:filament-table`, `make:filament-cluster`.
3. **Follow the existing project convention.** If the repo keeps schemas/tables embedded in the resource class (`file_generation.flags` in `config/filament.php`), keep doing that — do not "modernise" files you weren't asked to touch.
4. **Business logic never lives in a schema/table class.** Schemas describe UI. Put logic in the model, an action class, a service, or a job.
5. **Authorization is mandatory** on every resource. A resource without a policy is an incomplete feature.
6. **Comments, identifiers, commit messages: English only.**
7. After any structural change, run: `vendor/bin/pint`, `vendor/bin/phpstan analyse`, `php artisan filament:optimize-clear`, then the test suite.

---

## 2. v3 → v4 API map (memorise this table)

| Concept | ❌ v3 | ✅ v4 |
|---|---|---|
| Form signature | `form(Form $form)` → `$form->schema([...])` | `form(Schema $schema)` → `$schema->components([...])` |
| Infolist signature | `infolist(Infolist $infolist)` | `infolist(Schema $schema)` |
| Schema class | `Filament\Forms\Form` | `Filament\Schemas\Schema` |
| Layout components | `Filament\Forms\Components\{Grid,Section,Fieldset,Tabs,Wizard,Split,Flex}` | `Filament\Schemas\Components\*` |
| Inline actions in schema | `Filament\Forms\Components\Actions` | `Filament\Schemas\Components\Actions` |
| State utilities | `Filament\Forms\{Get,Set}` | `Filament\Schemas\Components\Utilities\{Get,Set}` |
| Table row actions | `->actions([...])` | `->recordActions([...])` |
| Table bulk actions | `->bulkActions([...])` | `->toolbarActions([...])` |
| Action classes | `Filament\Tables\Actions\EditAction` | `Filament\Actions\EditAction` (one unified namespace) |
| Icons | `->icon('heroicon-o-star')` | `->icon(Heroicon::OutlinedStar)` — `Filament\Support\Icons\Heroicon` |
| Nav icon property | `protected static ?string $navigationIcon` | `protected static string \| BackedEnum \| null $navigationIcon` |
| Model property | `protected static string $model` | `protected static ?string $model` |
| Modal form on an action | `->form([...])` | `->schema([...])` |

Magic strings (`'heroicon-o-*'`) still work but are **discouraged** — prefer the `Heroicon` enum for IDE completion and typo safety.

---

## 3. Behavioural defaults that changed in v4 (silent-bug territory)

These do not throw exceptions — they change runtime behaviour. Check each one when porting or reviewing code.

| Default | v4 behaviour | Opt out |
|---|---|---|
| `Grid` / `Section` / `Fieldset` width | Span **1 column**, not full width | `->columnSpanFull()` |
| `columnSpan(2)` | Targets `>= lg` breakpoints (same as `columns()`) | `->columnSpan(['lg' => 2, ...])` |
| Table filters | **Deferred** — user must click Apply | `->deferFilters(false)` |
| Table sorting | Automatic primary-key sort appended | `->defaultKeySort(false)` |
| Pagination | `'all'` option removed | `->paginationPageOptions([5, 10, 25, 50, 'all'])` |
| `unique()` | `ignoreRecord: true` by default | `unique(ignoreRecord: false)` |
| File visibility on non-local disks (s3) | `private` | `->visibility('public')` |
| Default disk | `FILESYSTEM_DISK` env var (was `FILAMENT_FILESYSTEM_DISK`) | edit `config/filament.php` |
| Enum-backed field state | Always the **enum instance**, never the scalar | type-hint `?MyEnum $state` |
| Tenancy | All panel queries auto-scoped + new records auto-associated | see tenancy docs |
| `Radio::inline()` | Only inlines the buttons, not the label | add `->inlineLabel()` |
| Import/export jobs | 3 retries, 60s backoff | override in the Importer/Exporter |

To restore a v3 default **globally**, use `configureUsing()` in `AppServiceProvider::boot()` — never patch it per-component across the codebase:

```php
use Filament\Tables\Table;

Table::configureUsing(fn (Table $table) => $table->deferFilters(false));
```

---

## 4. Directory structure (v4 default)

```
app/Filament/Resources/Users/
├── UserResource.php
├── Pages/
│   ├── ListUsers.php
│   ├── CreateUser.php
│   ├── EditUser.php
│   └── ViewUser.php
├── Schemas/
│   ├── UserForm.php
│   └── UserInfolist.php
├── Tables/
│   └── UsersTable.php
└── RelationManagers/
    └── PostsRelationManager.php
```

- One resource = one directory. Never dump `UserResource.php` next to `PostResource.php` with sibling `UserResource/` folders (that is the v3 layout).
- Migrating an existing v3 tree: `php artisan filament:upgrade-directory-structure-to-v4 --dry-run` first, then run PHPStan — the script cannot fix all same-namespace references.

---

## 5. Canonical resource skeleton

```php
<?php

namespace App\Filament\Resources\Users;

use App\Filament\Resources\Users\Pages\CreateUser;
use App\Filament\Resources\Users\Pages\EditUser;
use App\Filament\Resources\Users\Pages\ListUsers;
use App\Filament\Resources\Users\Schemas\UserForm;
use App\Filament\Resources\Users\Tables\UsersTable;
use App\Models\User;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class UserResource extends Resource
{
    protected static ?string $model = User::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedUsers;

    protected static ?string $recordTitleAttribute = 'name';

    public static function form(Schema $schema): Schema
    {
        return UserForm::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return UsersTable::configure($table);
    }

    // Eager-load here: this query backs the table, global search and record resolution.
    public static function getEloquentQuery(): Builder
    {
        return parent::getEloquentQuery()->with(['company', 'roles']);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListUsers::route('/'),
            'create' => CreateUser::route('/create'),
            'edit' => EditUser::route('/{record}/edit'),
        ];
    }
}
```

**Schema class:**

```php
<?php

namespace App\Filament\Resources\Users\Schemas;

use Filament\Forms\Components\TextInput;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;

class UserForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Identity')
                ->columnSpanFull()      // v4: sections are 1 column by default
                ->columns(2)
                ->schema([
                    TextInput::make('name')->required()->maxLength(255),
                    TextInput::make('email')
                        ->email()
                        ->required()
                        ->unique(ignoreRecord: true),   // explicit, even though it is the default
                ]),
        ]);
    }
}
```

**Table class:**

```php
<?php

namespace App\Filament\Resources\Users\Tables;

use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Actions\ViewAction;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class UsersTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('name')->searchable()->sortable(),
                TextColumn::make('company.name')->searchable()->sortable(),
                TextColumn::make('created_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->filters([])
            ->recordActions([
                ViewAction::make(),
                EditAction::make(),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make(),
                ]),
            ]);
    }
}
```

---

## 6. Schemas (forms + infolists)

- A `Schema` holds **components**, not "fields" — `->components([...])` at the top level, `->schema([...])` inside layout components.
- Reactivity: `->live()` for immediate updates, `->live(onBlur: true)` for text inputs, `->live(debounce: '500ms')` for search-like inputs. **Never** make an entire form live; it costs a round trip per keystroke.
- Conditional logic uses closures with injected utilities:
  ```php
  use Filament\Schemas\Components\Utilities\Get;
  use Filament\Schemas\Components\Utilities\Set;

  Select::make('country_id')->live(),
  Select::make('state_id')
      ->options(fn (Get $get) => State::query()->where('country_id', $get('country_id'))->pluck('name', 'id'))
      ->visible(fn (Get $get): bool => filled($get('country_id'))),
  ```
- `Select::make(...)->relationship(...)->searchable()->preload()` — only `preload()` when the option set is small (< ~100 rows); otherwise it fires a full query on every page load.
- Enum options: `->options(MyEnum::class)`; every callback receiving that state must type-hint `?MyEnum`, not `?string`.
- `->hidden()` still submits nothing but keeps state; `->disabled()` does not submit — use `->dehydrated(false)` when a disabled field must not be written.
- Extract repeated field groups into a static method or a reusable component class. Copy-pasting a 40-line `Section` twice is a rule violation.
- Layout components live in `Filament\Schemas\Components`; input fields stay in `Filament\Forms\Components`; infolist entries stay in `Filament\Infolists\Components`.

---

## 7. Tables

- **N+1 is the #1 Filament performance bug.** Any `TextColumn::make('relation.attribute')` requires eager loading via `getEloquentQuery()` (resource) or `->modifyQueryUsing()` (relation manager / standalone table).
- Do not run queries inside a column closure — it executes once per row.
- Use `->deferLoading()` on heavy tables so the page shell renders before the query runs.
- Searching a relationship column: `->searchable()` on a dotted column works; for anything custom use `->searchable(query: fn (Builder $query, string $search) => ...)`.
- Aggregates belong in the query (`withCount`, `withSum`), then `TextColumn::make('posts_count')` — never `$record->posts()->count()` in a closure.
- Filters are deferred by default; only disable that on small datasets with a written justification.
- Bulk actions on large selections: prefer `->action()` that dispatches a queued job over an in-request loop. Use `->authorizeIndividualRecords('delete')` so unauthorised records are dropped from `$records`.
- Never override the removed Livewire-level methods (`getTableRecordUrlUsing`, `getTableRecordClassesUsing`, `getTableRecordActionUsing`, `isTableRecordSelectable`) — use `$table->recordUrl()`, `->recordClasses()`, `->recordAction()`, `->checkIfRecordIsSelectableUsing()`.

---

## 8. Actions

- One namespace: `Filament\Actions\*` — for pages, tables, schemas, and relation managers alike.
- Modal content is defined with `->schema([...])`, and the callback receives `array $data`:
  ```php
  Action::make('refund')
      ->icon(Heroicon::OutlinedBanknotes)
      ->requiresConfirmation()
      ->schema([TextInput::make('reason')->required()])
      ->action(fn (Order $record, array $data) => app(RefundOrder::class)($record, $data['reason']))
      ->successNotificationTitle('Refund issued');
  ```
- Every destructive action MUST have `->requiresConfirmation()` and an authorization check (`->authorize()` or a policy ability).
- Long-running work goes to a queued job; the action only dispatches and notifies.
- Reusable actions: extend `Filament\Actions\Action` and override `setUp()` — **never** override `make()`.

---

## 9. Custom component classes

When extending `Field`, `Entry`, `Column`, `Constraint`, `ExportColumn`, `ImportColumn`, `MorphToSelect`, `Placeholder`, or `Builder\Block`:

- The signature is `public static function make(?string $name = null): static`.
- Set defaults in `setUp()` (call `parent::setUp()` first).
- Provide a default name via `getDefaultName()`, not by overriding `make()`.

---

## 10. Authorization & security

- Panel access: implement `FilamentUser::canAccessPanel()` on the `User` model. Do not rely on middleware alone.
- Resource permissions: **Laravel policies**. Filament resolves them automatically from the model.
- Do **not** override `canCreate()` / `canViewAny()` / `canDelete()` on a resource — v4 does not always call them. Put the logic in the policy, or override `getCreateAuthorizationResponse()` / `getViewAnyAuthorizationResponse()` / etc., which support policy response objects.
- Field-level control: `->visible(fn (): bool => auth()->user()->can('...'))` and `->disabled(...)`. Hiding a field is not authorization — always enforce server-side too.
- Tenancy: v4 auto-scopes queries and auto-associates new records. Do not add manual `where('tenant_id', ...)` scopes on top; verify isolation with a test instead.
- File uploads: validate `->acceptedFileTypes()` and `->maxSize()`. On S3-style disks files are private by default — serve them through temporary signed URLs rather than flipping visibility to public.

---

## 11. Performance checklist

- Eager-load every relationship touched by a column, infolist entry, or record title.
- `->deferLoading()` on heavy tables; `->deferFilters()` stays on (default).
- Widgets: cache expensive aggregates (`Cache::remember`), set `$pollingInterval = null` unless live data is genuinely required, and use `getEloquentQuery()` scoping.
- Production deploy: `php artisan filament:optimize` (component + icon cache) and `php artisan filament:optimize-clear` after any resource change during development.
- Avoid `'all'` pagination. Cap `paginationPageOptions()` sensibly.
- Global search: define `getGloballySearchableAttributes()` narrowly and index those columns; use `getGlobalSearchEloquentQuery()` for eager loading.

---

## 12. Styling / theme

- Filament v4 ships Tailwind CSS v4. There is **no `tailwind.config.js`** for a Filament theme — configuration lives in CSS.
- Theme file shape:
  ```css
  @import '../../../../vendor/filament/filament/resources/css/theme.css';

  @source '../../../../app/Filament/**/*';
  @source '../../../../resources/views/filament/**/*';
  ```
- Tailwind classes used in your own Blade/Livewire files are **not** compiled unless a custom theme exists (`php artisan make:filament-theme`) and a matching `@source` path is added. Adding a class to a custom Blade view without adding its `@source` path is a bug.
- Prefer Filament's own Blade components and design tokens over ad-hoc utility soup.

---

## 13. Testing (required for every resource)

Pest + Livewire helpers. Minimum coverage per resource:

```php
use function Pest\Livewire\livewire;

it('renders the list page', function () {
    livewire(ListUsers::class)->assertSuccessful();
});

it('creates a user', function () {
    $data = User::factory()->make();

    livewire(CreateUser::class)
        ->fillForm(['name' => $data->name, 'email' => $data->email])
        ->call('create')
        ->assertHasNoFormErrors();

    assertDatabaseHas(User::class, ['email' => $data->email]);
});

it('validates the email', function () {
    livewire(CreateUser::class)
        ->fillForm(['email' => 'not-an-email'])
        ->call('create')
        ->assertHasFormErrors(['email' => 'email']);
});
```

Also test: table search/filter/sort (`assertCanSeeTableRecords`, `filterTable`, `sortTable`), each custom action (`callAction`), and authorization for at least one allowed and one denied role.

---

## 14. Definition of done

- [ ] No `Filament\Forms\Form`, `Filament\Infolists\Infolist`, or `Filament\Tables\Actions\*` imports anywhere in the diff.
- [ ] `->recordActions()` / `->toolbarActions()` used; no `->actions()` / `->bulkActions()`.
- [ ] All layout components imported from `Filament\Schemas\Components`.
- [ ] Icons use the `Heroicon` enum.
- [ ] Every relationship column is eager-loaded.
- [ ] Policy exists and is covered by a test.
- [ ] Destructive actions confirm and authorize.
- [ ] `vendor/bin/pint` and `vendor/bin/phpstan analyse` are clean.
- [ ] `php artisan filament:optimize-clear` run; pages verified in the browser (v4 fails silently — blank sections and missing nav items rarely throw).
