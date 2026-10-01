# Authentication + Admin Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Email + password login/logout for admins and owners, and a mobile-first admin frame (bottom dock on phones, sidebar on desktop) styled with Tailwind + daisyUI `autumn`.

**Architecture:** Rails 8 `authentication` generator (DB-backed `sessions`, `Authentication` concern in `ApplicationController`, so every controller requires login unless it opts out), trimmed of password reset. `users` gains `name` and `role`. Admin controllers inherit an empty `Admin::BaseController` (scoping arrives in #18). Styling via `tailwindcss-rails` (standalone binary, no Node) with daisyUI loaded as a vendored `daisyui.mjs` plugin.

**Tech Stack:** Rails 8.1, Ruby 3.4, SQLite, bcrypt, tailwindcss-rails (Tailwind 4), daisyUI 5, Minitest 6, Capybara + Selenium headless Chrome.

**Spec:** `docs/superpowers/specs/2026-10-01-auth-admin-layout-design.md`

## Global Constraints

- Every shell command runs with `export PATH=~/.rbenv/shims:$PATH &&` prefixed (system Ruby is 2.6).
- All user-facing strings are Vietnamese, written inline (no locale file).
- No password reset, no mailer, no SMTP in this issue (moved to #23).
- No Node, no npm. daisyUI is the vendored file `app/assets/tailwind/daisyui.mjs`.
- Only the `autumn` theme: `@plugin "./daisyui.mjs" { themes: autumn --default; }`.
- `/v1/*` (inherits `ActionController::API`) and `/up` must stay reachable without login.
- Role values exactly `admin` | `owner`, default `owner`; labels "Quản trị viên" / "Chủ homestay".
- Passwords: minimum 8 characters.
- Test fixtures use made-up data (public repo). Fixture password for every user: `password123`.
- No `ponytail:` comments in code.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Login with different email casing / spaces** (`"  LAN@Example.com "`) must log in — owners type on phones with autocapitalize. Test in Task 2.
2. **Session of a deleted user** — the cookie must stop working, not raise. Test in Task 2.
3. **Logging out on one device** must not log out the user's other devices. Test in Task 2.
4. **Vietnamese names in the avatar** (`"Ánh"` → `"Á"`, multibyte) must render the right initial. Test in Task 3.
5. **Return to the page first requested** after login (visit `/admin` → login → back on `/admin`). Covered by the system test in Task 4.

Not testable here: the rate-limit message ("Thử lại sau ít phút") — `rate_limit` uses `Rails.cache`, which is `:null_store` in test.

---

## File Structure

| File | Responsibility |
|---|---|
| `db/migrate/*_create_users.rb`, `*_create_sessions.rb` | Generated; users gets `name`, `role` + check constraint |
| `app/models/user.rb` | Credentials, role enum, validations, `role_label`, `initial` |
| `app/models/session.rb`, `app/models/current.rb` | Generated, unchanged |
| `app/controllers/concerns/authentication.rb` | Generated; `after_authentication_url` → `/admin` |
| `app/controllers/sessions_controller.rb` | Generated; Vietnamese messages |
| `app/controllers/admin/base_controller.rb` | Parent of all admin controllers (empty for now) |
| `app/controllers/admin/dashboard_controller.rb` | `/admin` |
| `app/helpers/application_helper.rb` | `admin_menu_items` (single menu list) |
| `app/views/layouts/application.html.erb` | Frame: logged-out vs logged-in (navbar + dock / sidebar) |
| `app/views/shared/_icon.html.erb` | Inline Lucide SVGs |
| `app/views/sessions/new.html.erb` | Login page |
| `app/views/admin/dashboard/show.html.erb` | "Tổng quan" empty state |
| `app/assets/tailwind/application.css`, `daisyui.mjs` | Tailwind + daisyUI |
| `test/models/user_test.rb` | Model rules |
| `test/controllers/sessions_controller_test.rb` | Login/logout requests |
| `test/controllers/admin/dashboard_controller_test.rb` | Auth gate, menu, avatar |
| `test/application_system_test_case.rb`, `test/system/login_test.rb` | Browser login |

---

### Task 1: Users and sessions (generator, trimmed)

**Files:**
- Modify: `Gemfile` (uncomment bcrypt)
- Generated: `app/models/{user,session,current}.rb`, `app/controllers/concerns/authentication.rb`, `app/controllers/sessions_controller.rb`, `app/views/sessions/new.html.erb`, migrations, `config/routes.rb`
- Delete: everything for password reset the generator adds
- Modify: `db/migrate/*_create_users.rb`, `app/models/user.rb`
- Create/overwrite: `test/fixtures/users.yml`, `test/models/user_test.rb`

**Interfaces:**
- Produces: `User` with `email_address`, `name`, `role` (`admin?`/`owner?`), `role_label` → `"Quản trị viên"`/`"Chủ homestay"`, `initial` → first character of `name`, uppercased; fixtures `users(:admin)` (Trung, admin@example.com) and `users(:owner)` (Chị Lan, lan@example.com), password `password123`.

- [ ] **Step 1: Enable bcrypt and run the generator**

In `Gemfile`, change `# gem "bcrypt", "~> 3.1.7"` to `gem "bcrypt", "~> 3.1.7"`. Then:

```bash
export PATH=~/.rbenv/shims:$PATH && bundle install && bin/rails generate authentication && git status --short
```

- [ ] **Step 2: Remove password reset**

Delete every generated file whose path contains `password` (controller, mailer, views, mailer preview/test), e.g.:

```bash
git status --short | grep -i password
rm -rf app/controllers/passwords_controller.rb app/mailers/passwords_mailer.rb app/views/passwords app/views/passwords_mailer test/mailers/previews/passwords_mailer_preview.rb
```

In `config/routes.rb` delete the line `resources :passwords, param: :token`. Remove any "Forgot password?" link from `app/views/sessions/new.html.erb` (the whole view is replaced in Task 3). Re-run `git status --short | grep -i password` → no output.

- [ ] **Step 3: Write the failing model tests**

`test/fixtures/users.yml`:

```yaml
admin:
  email_address: admin@example.com
  name: Trung
  role: admin
  password_digest: <%= BCrypt::Password.create("password123") %>

owner:
  email_address: lan@example.com
  name: Chị Lan
  role: owner
  password_digest: <%= BCrypt::Password.create("password123") %>
```

`test/models/user_test.rb`:

```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build(**attrs)
    User.new(email_address: "new@example.com", name: "Chị Mai", password: "password123", **attrs)
  end

  test "valid with defaults; role defaults to owner" do
    user = build
    assert user.valid?
    assert user.owner?
  end

  test "requires name and email" do
    user = build(name: "", email_address: "")
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :name
    assert_includes user.errors.attribute_names, :email_address
  end

  test "normalizes and uniquely indexes email" do
    assert_equal "lan@example.com", build(email_address: "  LAN@Example.com ").email_address
    assert_not build(email_address: "LAN@example.com").valid?
  end

  test "password needs at least 8 characters" do
    assert_not build(password: "1234567").valid?
    assert build(password: "12345678").valid?
  end

  test "rejects unknown role in validation and in the database" do
    assert_not build(role: "staff").valid?
    assert_raises(ActiveRecord::StatementInvalid) { users(:owner).update_column(:role, "staff") }
  end

  test "role label and initial" do
    assert_equal "Quản trị viên", users(:admin).role_label
    assert_equal "Chủ homestay", users(:owner).role_label
    assert_equal "C", users(:owner).initial
    assert_equal "Á", build(name: "ánh").initial
  end
end
```

- [ ] **Step 4: Run to verify failure**

Run: `export PATH=~/.rbenv/shims:$PATH && bin/rails db:migrate && bin/rails test test/models/user_test.rb`
Expected: errors — `name`/`role` columns missing (fixtures fail to load) or `role_label` undefined.

- [ ] **Step 5: Add columns and model rules**

Roll back, then edit the generated `db/migrate/*_create_users.rb` (unmerged migration, so edit in place):

```bash
export PATH=~/.rbenv/shims:$PATH && bin/rails db:rollback STEP=2
```

```ruby
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.string :role, null: false, default: "owner"

      t.timestamps

      t.check_constraint "role IN ('admin', 'owner')", name: "users_role_values"
    end
    add_index :users, :email_address, unique: true
  end
end
```

`app/models/user.rb`:

```ruby
class User < ApplicationRecord
  ROLE_LABELS = { "admin" => "Quản trị viên", "owner" => "Chủ homestay" }.freeze

  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  enum :role, { admin: "admin", owner: "owner" }, validate: true

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true

  def role_label = ROLE_LABELS.fetch(role)

  def initial = name.to_s.first.to_s.upcase
end
```

- [ ] **Step 6: Run to verify pass**

Run: `export PATH=~/.rbenv/shims:$PATH && bin/rails db:migrate && bin/rails test test/models/user_test.rb && grep -n "users_role_values" db/schema.rb`
Expected: all pass; the check constraint is in `db/schema.rb`.

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock app/models app/controllers app/views/sessions config/routes.rb db test/fixtures/users.yml test/models/user_test.rb
git status --short   # anything else generated (e.g. test helpers) — review, then add or delete
git commit -m "Add users and sessions via Rails authentication generator

Password reset removed (moved to #23). Users get name and role
(admin|owner, DB check + validated enum) and a 8-character password
minimum.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Login flow, routes, admin controllers

**Files:**
- Modify: `app/controllers/sessions_controller.rb`, `app/controllers/concerns/authentication.rb`, `config/routes.rb`
- Create: `app/controllers/admin/base_controller.rb`, `app/controllers/admin/dashboard_controller.rb`, `app/views/admin/dashboard/show.html.erb` (minimal; styled in Task 3)
- Create/overwrite: `test/controllers/sessions_controller_test.rb`, `test/controllers/admin/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `User`, fixtures from Task 1; generator's `start_new_session_for`, `terminate_session`, `authenticated?`, `Current.user`.
- Produces: routes `new_session_path` (`/session/new`), `session_path` (`/session`, POST/DELETE), `admin_root_path` (`/admin`), `root` → `/admin`; `Admin::BaseController`.

- [ ] **Step 1: Write the failing request tests**

`test/controllers/sessions_controller_test.rb`:

```ruby
require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  def log_in(email, password = "password123")
    post session_path, params: { email_address: email, password: password }
  end

  test "login page renders" do
    get new_session_path
    assert_response :success
    assert_select "h1, h2", text: "Đăng nhập"
  end

  test "correct credentials start a session and go to admin" do
    assert_difference -> { users(:owner).sessions.count }, 1 do
      log_in "lan@example.com"
    end
    assert_redirected_to admin_root_url
  end

  test "email casing and spaces don't matter" do
    log_in "  LAN@Example.com "
    assert_redirected_to admin_root_url
  end

  test "wrong password goes back to login with an error and no session" do
    assert_no_difference -> { Session.count } do
      log_in "lan@example.com", "wrong-password"
    end
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=alert]", text: /Email hoặc mật khẩu không đúng/
  end

  test "logout ends only this device's session" do
    other_device = users(:owner).sessions.create!(ip_address: "1.1.1.1", user_agent: "phone")
    log_in "lan@example.com"

    delete session_path

    assert_redirected_to new_session_path
    assert_equal [ other_device ], users(:owner).sessions.reload.to_a
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "session of a deleted user no longer works" do
    log_in "lan@example.com"
    users(:owner).destroy!
    get admin_root_path
    assert_redirected_to new_session_path
  end
end
```

`test/controllers/admin/dashboard_controller_test.rb`:

```ruby
require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "requires login" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "root redirects to admin" do
    get root_path
    assert_redirected_to "/admin"
  end

  test "shows the dashboard to a logged-in user" do
    log_in users(:owner)
    get admin_root_path
    assert_response :success
    assert_select "h1", "Tổng quan"
  end

  test "public endpoints stay public" do
    get "/v1/vacancy"
    assert_response :success
    get "/up"
    assert_response :success
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `export PATH=~/.rbenv/shims:$PATH && bin/rails test test/controllers/sessions_controller_test.rb test/controllers/admin/dashboard_controller_test.rb`
Expected: errors — `admin_root_url` undefined, English alert text.

- [ ] **Step 3: Implement**

`config/routes.rb` — replace the generated `resource :session` line and add, above the `v1` namespace:

```ruby
  resource :session, only: %i[new create destroy]

  namespace :admin do
    root "dashboard#show"
  end

  root to: redirect("/admin")
```

`app/controllers/sessions_controller.rb` — change the two English messages:

```ruby
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Thử lại sau ít phút." }
```

```ruby
      redirect_to new_session_path, alert: "Email hoặc mật khẩu không đúng."
```

`app/controllers/concerns/authentication.rb` — in `after_authentication_url`, replace `root_url` with `admin_root_url`:

```ruby
    def after_authentication_url
      session.delete(:return_to_after_authenticating) || admin_root_url
    end
```

`app/controllers/admin/base_controller.rb`:

```ruby
# Parent of every /admin controller. Access scoping (accessible_place_ids, 404) arrives in #18.
class Admin::BaseController < ApplicationController
end
```

`app/controllers/admin/dashboard_controller.rb`:

```ruby
class Admin::DashboardController < Admin::BaseController
  def show
  end
end
```

`app/views/admin/dashboard/show.html.erb` (styled in Task 3):

```erb
<h1>Tổng quan</h1>
```

`app/views/sessions/new.html.erb` (generated, English) — two minimal edits so Task 2's tests can pass; the whole view is replaced in Task 3:
- change the heading text to `Đăng nhập` (keep it an `h1`);
- render the alert as `<% if alert %><div role="alert"><%= alert %></div><% end %>` instead of the generated `<p style="color: red">…</p>`.

- [ ] **Step 4: Run to verify pass**

Run: `export PATH=~/.rbenv/shims:$PATH && bin/rails test`
Expected: all pass (existing 63 + new).

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers app/views test/controllers
git commit -m "Add login flow, admin namespace and Vietnamese messages

Every controller requires login by default; /v1 and /up stay public.
Admin::BaseController is the parent for all admin controllers.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Tailwind + daisyUI, admin frame and pages

**Files:**
- Modify: `Gemfile`, `.gitignore` (by installer), `bin/dev`/`Procfile.dev` (by installer)
- Create: `app/assets/tailwind/application.css`, `app/assets/tailwind/daisyui.mjs`
- Delete: `app/assets/stylesheets/application.css`
- Modify: `app/views/layouts/application.html.erb`, `app/helpers/application_helper.rb`
- Create: `app/views/shared/_icon.html.erb`
- Overwrite: `app/views/sessions/new.html.erb`, `app/views/admin/dashboard/show.html.erb`
- Modify: `test/controllers/admin/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `Current.user`, `authenticated?`, `User#role_label`, `User#initial`, `admin_root_path`, `session_path`, `new_session_path`.
- Produces: `admin_menu_items` → array of `{ label:, icon:, path: }` hashes (`path: nil` = not built yet); partial `shared/icon` with local `name:` in `%w[home calendar refresh users]`.

- [ ] **Step 1: Write the failing tests** (append to `test/controllers/admin/dashboard_controller_test.rb`)

```ruby
  test "owner sees menu without users item; disabled items are not links" do
    log_in users(:owner)
    get admin_root_path

    assert_select "aside a[href='/admin']", text: /Tổng quan/
    assert_select "aside", text: /Lịch phòng/
    assert_select "aside a", text: /Lịch phòng/, count: 0
    assert_select "aside", text: /Người dùng/, count: 0
    assert_select ".dock a[href='/admin']"
  end

  test "admin also sees the users item" do
    log_in users(:admin)
    get admin_root_path
    assert_select "aside", text: /Người dùng/
  end

  test "shows name, role and avatar initial, including Vietnamese letters" do
    users(:owner).update!(name: "ánh")
    log_in users(:owner)
    get admin_root_path

    assert_select ".avatar", text: "Á"
    assert_select "aside", text: /ánh/
    assert_select "aside", text: /Chủ homestay/
    assert_select "aside button", text: "Đăng xuất"
  end

  test "dashboard shows the empty state" do
    log_in users(:owner)
    get admin_root_path
    assert_select "main", text: /Chưa có homestay nào/
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `export PATH=~/.rbenv/shims:$PATH && bin/rails test test/controllers/admin/dashboard_controller_test.rb`
Expected: 4 failures (no `aside`, `.dock`, `.avatar`, empty state).

- [ ] **Step 3: Install Tailwind and daisyUI**

```bash
export PATH=~/.rbenv/shims:$PATH && bundle add tailwindcss-rails && bin/rails tailwindcss:install
curl -sLo app/assets/tailwind/daisyui.mjs https://github.com/saadeghi/daisyui/releases/latest/download/daisyui.mjs
head -c 300 app/assets/tailwind/daisyui.mjs   # note the daisyUI version for the commit message
git rm -q app/assets/stylesheets/application.css
```

`app/assets/tailwind/application.css` (replace the installer's content):

```css
@import "tailwindcss";
@plugin "./daisyui.mjs" {
  themes: autumn --default;
}
```

Check the installer added `/app/assets/builds/*` to `.gitignore` and a `css:` line to `Procfile.dev`. Run `bin/rails tailwindcss:build` → `app/assets/builds/tailwind.css` exists.

- [ ] **Step 4: Menu helper**

`app/helpers/application_helper.rb`:

```ruby
module ApplicationHelper
  # Single source for the admin dock (phone) and sidebar (desktop). path: nil = page not built yet.
  def admin_menu_items
    items = [
      { label: "Tổng quan", icon: "home", path: admin_root_path },
      { label: "Lịch phòng", icon: "calendar", path: nil },
      { label: "Kênh OTA", icon: "refresh", path: nil }
    ]
    items << { label: "Người dùng", icon: "users", path: nil } if Current.user&.admin?
    items
  end
end
```

- [ ] **Step 5: Icon partial**

`app/views/shared/_icon.html.erb` (Lucide, MIT):

```erb
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="size-5" aria-hidden="true">
  <% case name %>
  <% when "home" %>
    <path d="M3 10.5 12 3l9 7.5V21a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z"/>
  <% when "calendar" %>
    <rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>
  <% when "refresh" %>
    <path d="M21 12a9 9 0 0 1-15.5 6.2L3 16M3 12a9 9 0 0 1 15.5-6.2L21 8M21 3v5h-5M3 21v-5h5"/>
  <% when "users" %>
    <circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0M16 4a4 4 0 0 1 0 8M22 21a7 7 0 0 0-5-6.7"/>
  <% end %>
</svg>
```

- [ ] **Step 6: Layout**

`app/views/layouts/application.html.erb`:

```erb
<!DOCTYPE html>
<html lang="vi" data-theme="autumn">
  <head>
    <title><%= content_for(:title) || "hueni admin" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="application-name" content="hueni admin">
    <meta name="mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= yield :head %>
    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body class="min-h-screen bg-base-200 text-base-content">
    <% if authenticated? %>
      <% user = Current.user %>
      <div class="lg:flex">
        <aside class="hidden lg:flex lg:flex-col w-60 min-h-screen bg-base-100 border-r border-base-300 sticky top-0">
          <div class="px-5 py-4 text-xl font-bold text-primary">hueni</div>
          <ul class="menu w-full gap-1">
            <% admin_menu_items.each do |item| %>
              <% if item[:path] %>
                <li><%= link_to item[:path], class: ("menu-active" if current_page?(item[:path])) do %><%= render "shared/icon", name: item[:icon] %><%= item[:label] %><% end %></li>
              <% else %>
                <li class="menu-disabled"><span><%= render "shared/icon", name: item[:icon] %><%= item[:label] %> <span class="badge badge-ghost badge-xs">Sắp có</span></span></li>
              <% end %>
            <% end %>
          </ul>
          <div class="mt-auto p-4 border-t border-base-300 text-sm">
            <div class="font-semibold"><%= user.name %></div>
            <div class="opacity-60 mb-2"><%= user.role_label %></div>
            <%= button_to "Đăng xuất", session_path, method: :delete, class: "btn btn-ghost btn-sm w-full justify-start" %>
          </div>
        </aside>

        <div class="flex-1 min-w-0">
          <div class="navbar bg-base-100 shadow-sm px-4 lg:hidden">
            <div class="flex-1 text-xl font-bold text-primary">hueni</div>
            <div class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="avatar avatar-placeholder">
                <div class="bg-primary text-primary-content w-9 rounded-full"><span><%= user.initial %></span></div>
              </div>
              <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-56 p-2 shadow-md">
                <li class="menu-title"><span><%= user.name %> · <%= user.role_label %></span></li>
                <li><%= button_to "Đăng xuất", session_path, method: :delete %></li>
              </ul>
            </div>
          </div>

          <main class="max-w-3xl mx-auto p-4 pb-24 lg:p-8">
            <% flash.each do |type, message| %>
              <div role="alert" class="alert <%= type == "alert" ? "alert-error" : "alert-success" %> alert-soft mb-4"><%= message %></div>
            <% end %>
            <%= yield %>
          </main>
        </div>
      </div>

      <div class="dock dock-sm bg-base-100 border-t border-base-300 lg:hidden">
        <% admin_menu_items.each do |item| %>
          <% if item[:path] %>
            <%= link_to item[:path], class: ("dock-active text-primary" if current_page?(item[:path])) do %><%= render "shared/icon", name: item[:icon] %><span class="dock-label"><%= item[:label] %></span><% end %>
          <% else %>
            <span class="opacity-40" aria-disabled="true"><%= render "shared/icon", name: item[:icon] %><span class="dock-label"><%= item[:label] %></span></span>
          <% end %>
        <% end %>
      </div>
    <% else %>
      <main class="min-h-screen flex flex-col justify-center px-4 py-8">
        <div class="w-full max-w-sm mx-auto">
          <% flash.each do |type, message| %>
            <div role="alert" class="alert <%= type == "alert" ? "alert-error" : "alert-success" %> alert-soft mb-4"><%= message %></div>
          <% end %>
          <%= yield %>
        </div>
      </main>
    <% end %>
  </body>
</html>
```

- [ ] **Step 7: Pages**

`app/views/sessions/new.html.erb`:

```erb
<% content_for :title, "Đăng nhập · hueni admin" %>

<div class="text-center mb-6">
  <div class="text-3xl font-bold text-primary">hueni</div>
  <div class="text-sm opacity-70">Quản lý phòng cho chủ homestay</div>
</div>

<div class="card bg-base-100 shadow-md">
  <div class="card-body">
    <h1 class="card-title">Đăng nhập</h1>
    <%= form_with url: session_path, class: "flex flex-col gap-3" do |form| %>
      <div>
        <%= form.label :email_address, "Email", class: "label mb-1" %>
        <%= form.email_field :email_address, required: true, autofocus: true, autocomplete: "username", value: params[:email_address], class: "input w-full" %>
      </div>
      <div>
        <%= form.label :password, "Mật khẩu", class: "label mb-1" %>
        <%= form.password_field :password, required: true, autocomplete: "current-password", maxlength: 72, class: "input w-full" %>
      </div>
      <%= form.submit "Đăng nhập", class: "btn btn-primary btn-block mt-2" %>
    <% end %>
  </div>
</div>
```

`app/views/admin/dashboard/show.html.erb`:

```erb
<% content_for :title, "Tổng quan · hueni admin" %>

<h1 class="text-xl font-semibold mb-4">Tổng quan</h1>

<div class="card bg-base-100 border border-dashed border-base-300">
  <div class="card-body items-center text-center py-10">
    <%= render "shared/icon", name: "home" %>
    <div class="font-semibold">Chưa có homestay nào</div>
    <div class="text-sm opacity-70">Quản trị viên sẽ gán homestay cho tài khoản của bạn.</div>
  </div>
</div>
```

Update the Task 2 assertion in `sessions_controller_test.rb` if needed: the login title is now an `h1` (the `"h1, h2"` selector already matches).

- [ ] **Step 8: Run to verify pass**

Run: `export PATH=~/.rbenv/shims:$PATH && bin/rails tailwindcss:build && bin/rails test && bin/rubocop && bin/brakeman --no-pager -q`
Expected: all tests pass; no offenses; no warnings.

- [ ] **Step 9: Look at it**

Run `bin/dev`, create a user in `bin/rails console` (`User.create!(email_address: "me@example.com", name: "Trung", password: "password123", role: "admin")`), open `http://localhost:3000`, log in, check phone width (devtools, 390 px: navbar + dock) and desktop width (sidebar). Stop the server.

- [ ] **Step 10: Commit**

```bash
git add Gemfile Gemfile.lock .gitignore Procfile.dev bin/dev app/assets app/helpers app/views test/controllers
git status --short   # app/assets/builds must NOT appear (git-ignored)
git commit -m "Add Tailwind + daisyUI admin frame with login page

daisyUI <version> vendored as app/assets/tailwind/daisyui.mjs (no Node),
autumn theme only. Phones get a bottom dock, desktop a sidebar, both
from admin_menu_items; unbuilt pages show as disabled.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: System test — log in through the browser

**Files:**
- Create: `test/application_system_test_case.rb`, `test/system/login_test.rb`

**Interfaces:**
- Consumes: routes and views from Tasks 2–3; fixture `users(:owner)` (lan@example.com / password123).

- [ ] **Step 1: Write the system test**

`test/application_system_test_case.rb`:

```ruby
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]
end
```

`test/system/login_test.rb`:

```ruby
require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  test "owner logs in, lands on the page they asked for, and logs out" do
    visit admin_root_path
    assert_current_path new_session_path

    fill_in "Email", with: "lan@example.com"
    fill_in "Mật khẩu", with: "password123"
    click_button "Đăng nhập"

    assert_current_path admin_root_path
    assert_selector "h1", text: "Tổng quan"
    assert_text "Chị Lan"

    click_button "Đăng xuất"
    assert_current_path new_session_path
  end

  test "wrong password shows the error" do
    visit new_session_path
    fill_in "Email", with: "lan@example.com"
    fill_in "Mật khẩu", with: "wrong-password"
    click_button "Đăng nhập"

    assert_text "Email hoặc mật khẩu không đúng"
  end
end
```

- [ ] **Step 2: Run it**

Run: `export PATH=~/.rbenv/shims:$PATH && bin/rails test:system`
Expected: 2 runs, 0 failures. (At 1400 px wide only the sidebar's "Đăng xuất" is visible, so `click_button` is unambiguous.) If Chrome is missing locally, report it — CI's `system-test` job runs it.

- [ ] **Step 3: Verify the CSS build works from a clean state** (CI has no prebuilt CSS)

Run: `rm -rf app/assets/builds/*.css && export PATH=~/.rbenv/shims:$PATH && bin/rails db:test:prepare test test:system`
Expected: passes (tailwindcss-rails hooks the build into `test:prepare`). If it fails with a missing `tailwind.css`, add `bin/rails tailwindcss:build` before the test commands in `.github/workflows/ci.yml` for both `test` and `system-test` jobs.

- [ ] **Step 4: Commit**

```bash
git add test/application_system_test_case.rb test/system .github/workflows/ci.yml
git commit -m "Add system test for login and logout

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Docs and issues

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In "What this is", item 2: replace `(Hotwire, not built yet)` with `(Hotwire; login + frame built, pages in #18–#23)`.

In "Commands", after `bin/dev`, change its comment to `# http://localhost:3000 (server + Tailwind watcher)`.

In "Architecture", add a paragraph:

```markdown
**Auth & admin:** Rails 8 authentication generator (`Authentication` concern in `ApplicationController`, DB-backed `sessions`) — every controller requires login unless it calls `allow_unauthenticated_access`. `users.role` = `admin` | `owner`. Admin controllers inherit `Admin::BaseController` (scoping in #18). The admin menu is one list, `ApplicationHelper#admin_menu_items`, rendered as a bottom dock on phones and a sidebar on `lg+`; `path: nil` items show as "Sắp có". No password reset / mailer yet (#23).
```

In "Conventions", replace the line starting `- All user-facing strings in Vietnamese. Admin UI:` with:

```markdown
- All user-facing strings in Vietnamese, inline in views/controllers. Admin UI: server-rendered ERB + Turbo/Stimulus via importmap, **Tailwind 4 + daisyUI 5 (`autumn` theme only)** via `tailwindcss-rails`; daisyUI is the vendored `app/assets/tailwind/daisyui.mjs` (update by re-downloading). Mobile-first. The admin does not follow hueni's design.
```

In "Security invariants", replace the "Planned admin rule" line with:

```markdown
- Admin rule: every `/admin` controller inherits `Admin::BaseController`; from #18 it scopes through `Current.user.accessible_place_ids` and returns 404 out of scope.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document auth and admin styling in CLAUDE.md

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Update issues** (outward-facing — do after the user approves the PR step)

- #17 body: replace the styling line with `- Admin layout: Tailwind + daisyUI 5 (theme autumn), mobile-first (bottom dock on phones, sidebar on desktop); Vietnamese strings` and change "Done when" to `login/logout work; system test covers login. (Password reset moved to #23.)`
- #23 body: add a bullet `- Password reset (email link) — moved from #17`.

- [ ] **Step 4: Final verification, push, PR**

```bash
export PATH=~/.rbenv/shims:$PATH && bin/rails test && bin/rails test:system && bin/rubocop && bin/brakeman --no-pager -q && bin/bundler-audit
git push -u origin 17-auth-admin-layout
gh pr create --base main --title "Add authentication and admin layout" --body-file <scratchpad>/pr17.md
# pr17.md: "Closes #17", a Summary (one bullet per task above), a Test plan (unit/request/system counts + rubocop/brakeman/bundler-audit),
# and the Claude Code attribution line.
```
