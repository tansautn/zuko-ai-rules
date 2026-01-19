---
trigger: glob
globs: *.php *.py
---

# RULE: REPO & LAZY DI IN LARAVEL/PHP App

## 1. CORE ARCHITECTURE PRINCIPLES
*   **Models:** Only for data holding & relationship definitions.
*   **Repositories:** The **ONLY** layer for database interaction.
*   **Services/Jobs/Widgets:** Must use Repositories via Lazy Injection.
*   **Strict Prohibitions:** No `Model::find()`, `Model::where()`, or `Model::query()` in business logic.

---

## 2. REPOSITORY USAGE & INSTANTIATION
### Pattern Enforcement
*   **Instantiation:** Use `Repository::make()` (SingletonMakeable) or `app(Repository::class)`.
*   **Abstract Methods:** Utilize `create()`, `update()`, `find()`, `findOneBy()`.
*   **Query Builders:**
    *   `getIsolatedQuery()`: For fresh, independent queries.
    *   `getCurrentQuery()`: For chained operations (must reset with `null` after use).

### Optimization & Performance
*   **Mass Updates:** 
    *   Avoid direct `QueryBuilder->update()`. 
    *   Use `LazyCollection` + loop `save()` on each Eloquent model to fire Model Events.
    *   **Transactions:** Wrap in `DB::beginTransaction()`. Commit every `x` records using `%` operator. 
    *   **Error Handling:** Rollback on critical failures; ensure partial success for non-SQL errors.
*   **N+1 Prevention:** 
    *   Always use `with(['relation' => fn($q) => $q->select('id', 'fk')])` before loops.
    *   For ID-only access: Use `$model->relation->pluck('id')`.

---

## 3. LAZY DEPENDENCY INJECTION (DI)
**Objective:** Reduce memory footprint & prevent Factory/CI initialization issues.

### ❌ Anti-Pattern (Constructor Injection)
Do **NOT** inject dependencies directly into `__construct()`.

### ✅ Standard: Getter-Based Lazy Loading (Recommended)
Implement dependencies as nullable properties and resolve them via getter methods.

```php
protected ?ServiceOrRepo $dependency = null;

protected function getDependency(): ServiceOrRepo {
    if (!$this->dependency instanceof ServiceOrRepo) {
        $this->dependency = app()->make(ServiceOrRepo::class);
    }
    return $this->dependency;
}
```

### ✅ Standard: Single-Line Call
For simple usage, use the `SingletonMakeable` trait: `ServiceClass::make()->method()`.

---

## 4. IMPLEMENTATION TEMPLATES

### Repository Structure
```php
class WalletRepository extends AbstractRepository {
    public function getModelClassName() => Wallet::class;

    public function getActiveWallets(): Collection {
        return $this->getIsolatedQuery()->where('status', 'active')->get();
    }
}
```

### Optimized Batch Update Pattern
```php
DB::transaction(function () {
    $this->repo->getIsolatedQuery()->cursor() // LazyCollection
        ->each(function ($model, $index) {
            $model->update(['status' => 'processed']);
            if ($index % 100 === 0) { /* Optional: Intermediate logic */ }
        });
});
```

### Service with Lazy DI
```php
class TransactionService {
    protected ?TransactionRepository $repo = null;

    protected function getRepo(): TransactionRepository {
        return $this->repo ??= TransactionRepository::make();
    }

    public function process(int $id) {
        return $this->getRepo()->find($id);
    }
}
```

---

## 5. TESTING & VALIDATION
*   Test Repository methods directly.
*   Do **NOT** test Model methods for data retrieval.
*   Seeders: The only exception where direct Model usage is allowed for initial data seeding.

---

**User Note:** *Hãy áp dụng các quy tắc này một cách nghiêm ngặt. Ưu tiên sự chính xác của Repository Pattern và tính hiệu quả của Lazy DI.*