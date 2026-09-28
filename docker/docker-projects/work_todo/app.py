from flask import Flask, render_template, request, redirect, url_for, jsonify
import json
import os
import tempfile

app = Flask(__name__)

TODO_FILE       = '/app/data/todos.json'
STATS_FILE      = '/app/data/stats.json'
CATEGORIES_FILE = '/app/data/categories.json'

# Built-in categories seeded on first run. 'General' is the fallback and must stay
# last and undeletable so every task always has a valid home.
DEFAULT_CATEGORIES = [
    {'name': 'Projects',            'icon': '📁'},
    {'name': 'Planning',            'icon': '🗺️'},
    {'name': 'Meetings/Follow-ups', 'icon': '📅'},
    {'name': 'Documentation',       'icon': '📄'},
    {'name': 'Research',            'icon': '🔍'},
    {'name': 'General',             'icon': '📝'},
]
DEFAULT_CATEGORY_NAMES = {c['name'] for c in DEFAULT_CATEGORIES}
DEFAULT_ICON           = '🏷️'   # given to custom categories added without an emoji


# FILE HELPERS

def _atomic_write(path, data):
    """Write JSON to a temp file then rename so a power cut never corrupts the target."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    dir_ = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=dir_)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except Exception:
        os.unlink(tmp)
        raise


# STATS PERSISTENCE

def load_stats():
    if os.path.exists(STATS_FILE):
        with open(STATS_FILE, 'r') as f:
            return json.load(f)
    return {'deleted_done_count': 0}


def save_stats(stats):
    _atomic_write(STATS_FILE, stats)


# CATEGORY PERSISTENCE (user-editable list of categories)

def load_categories():
    """Load categories, seeding the built-in defaults on first run.

    Returns a list of {'name', 'icon'} dicts. 'General' is always present and
    forced to the end so it stays the standing fallback category.
    """
    if os.path.exists(CATEGORIES_FILE):
        with open(CATEGORIES_FILE, 'r') as f:
            cats = json.load(f)
    else:
        cats = [dict(c) for c in DEFAULT_CATEGORIES]
        save_categories(cats)

    # Guarantee a General category exists and sits last
    others  = [c for c in cats if c['name'] != 'General']
    general = next((c for c in cats if c['name'] == 'General'), {'name': 'General', 'icon': '📝'})
    return others + [general]


def save_categories(categories):
    _atomic_write(CATEGORIES_FILE, categories)


# CATEGORY AND PRIORITY MANAGEMENT

def auto_assign_category(task):
    task_lower = task.lower()

    if any(w in task_lower for w in ['project', 'initiative', 'milestone', 'deliverable', 'epic', 'feature']):
        return 'Projects'

    if any(w in task_lower for w in ['plan', 'planning', 'roadmap', 'sprint', 'backlog', 'scope', 'jira', 'ticket']):
        return 'Planning'

    if any(w in task_lower for w in ['meeting', 'follow up', 'follow-up', 'action item', 'standup', 'sync', 'call', 'email', 'reply', 'respond', 'schedule']):
        return 'Meetings/Follow-ups'

    if any(w in task_lower for w in ['doc', 'documentation', 'write', 'readme', 'wiki', 'confluence', 'report', 'deck', 'slides', 'presentation']):
        return 'Documentation'

    if any(w in task_lower for w in ['research', 'investigate', 'explore', 'look into', 'evaluate', 'poc', 'proof of concept', 'prototype']):
        return 'Research'

    return 'General'


def migrate_todos(todos):
    migrated = False
    for index, todo in enumerate(todos):
        if 'category' not in todo:
            todo['category'] = auto_assign_category(todo['task'])
            migrated = True
        if 'priority' not in todo:
            todo['priority'] = 'Medium'
            migrated = True
        if 'notes' not in todo:
            todo['notes'] = ''
            migrated = True
        if 'parent_id' not in todo:
            todo['parent_id'] = None
            migrated = True
        # 'order' drives manual drag-and-drop sorting within a category
        if 'order' not in todo:
            todo['order'] = index
            migrated = True
    return todos, migrated


def calculate_metrics(todos, stats=None):
    if stats is None:
        stats = {'deleted_done_count': 0}

    deleted_done    = stats.get('deleted_done_count', 0)
    current_done    = sum(1 for t in todos if t['done'])
    current_pending = sum(1 for t in todos if not t['done'])
    completed_tasks = current_done + deleted_done
    total_tasks     = len(todos) + deleted_done
    completion_pct  = (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0
    high_priority   = sum(1 for t in todos if not t['done'] and t.get('priority') == 'High')

    return {
        'total': total_tasks,
        'pending': current_pending,
        'completed': completed_tasks,
        'completion_percentage': round(completion_pct, 1),
        'high_priority_pending': high_priority
    }


def build_hierarchy(todos):
    """Organizes a category's todos into parent/child structure for the category view."""
    by_id              = {t['id']: t for t in todos}
    children_by_parent = {}
    top_level          = []

    for todo in todos:
        pid = todo.get('parent_id')
        if pid is not None and pid in by_id:
            children_by_parent.setdefault(pid, []).append(todo)
        else:
            top_level.append(todo)

    result = []
    for todo in top_level:
        children  = children_by_parent.get(todo['id'], [])
        is_parent = bool(children)

        # Manual drag order governs the sequence within a parent
        children_sorted = sorted(children, key=lambda c: c.get('order', 0))

        # Tasks with no children can be linked to a parent; parents cannot
        ep = [t for t in top_level if t['id'] != todo['id']] if not is_parent else []

        child_items = []
        for c in children_sorted:
            c_ep = [t for t in top_level if t['id'] != c['id']]
            child_items.append({'todo': c, 'eligible_parents': c_ep})

        result.append({
            'todo':             todo,
            'children':         child_items,
            'eligible_parents': ep,
            'is_parent':        is_parent,
        })

    # Manual drag order governs the sequence of top-level items
    return sorted(result, key=lambda item: item['todo'].get('order', 0))


# FILE I/O

def load_todos():
    if os.path.exists(TODO_FILE):
        with open(TODO_FILE, 'r') as f:
            todos = json.load(f)
        todos, migrated = migrate_todos(todos)
        if migrated:
            save_todos(todos)
        return todos
    return []


def save_todos(todos):
    _atomic_write(TODO_FILE, todos)


# ROUTES

@app.route('/')
def index():
    todos      = load_todos()
    stats      = load_stats()
    metrics    = calculate_metrics(todos, stats)
    sort       = request.args.get('sort', 'category')
    categories = load_categories()
    cat_names  = [c['name'] for c in categories]
    cat_icons  = {c['name']: c['icon'] for c in categories}

    grouped_todos = {}
    if sort == 'urgency':
        for priority in ['High', 'Medium', 'Low']:
            priority_todos = [t for t in todos if t.get('priority') == priority]
            if priority_todos:
                # Flat items wrapped in hierarchy shape for template consistency
                grouped_todos[priority] = [
                    {'todo': t, 'children': [], 'eligible_parents': [], 'is_parent': False}
                    for t in sorted(priority_todos, key=lambda t: t.get('order', 0))
                ]
    else:
        for category in cat_names:
            category_todos = [t for t in todos if t.get('category') == category]
            if category_todos:
                grouped_todos[category] = build_hierarchy(category_todos)
            elif category not in DEFAULT_CATEGORY_NAMES:
                # Show empty custom categories so a freshly created one stays
                # visible (and deletable) before any task is assigned to it
                grouped_todos[category] = []

    return render_template('index.html',
                           todos=todos,
                           metrics=metrics,
                           grouped_todos=grouped_todos,
                           sort=sort,
                           categories=categories,
                           cat_icons=cat_icons,
                           default_category_names=DEFAULT_CATEGORY_NAMES)


@app.route('/add', methods=['POST'])
def add_todo():
    task     = request.form.get('task')
    category = request.form.get('category', 'General')
    priority = request.form.get('priority', 'Medium')

    if task:
        todos = load_todos()
        todos.append({
            'task':      task,
            'done':      False,
            'id':        len(todos),
            'category':  category,
            'priority':  priority,
            'notes':     '',
            'parent_id': None,
            'order':     len(todos),   # new tasks land at the bottom of their category
        })
        save_todos(todos)
    return redirect(url_for('index'))


@app.route('/toggle/<int:todo_id>')
def toggle_todo(todo_id):
    todos = load_todos()
    if 0 <= todo_id < len(todos):
        todos[todo_id]['done'] = not todos[todo_id]['done']
        save_todos(todos)
    return redirect(url_for('index'))


@app.route('/update_priority/<int:todo_id>', methods=['POST'])
def update_priority(todo_id):
    priority = request.form.get('priority')
    sort     = request.form.get('sort', 'category')
    if priority in ['High', 'Medium', 'Low']:
        todos = load_todos()
        if 0 <= todo_id < len(todos):
            todos[todo_id]['priority'] = priority
            save_todos(todos)
    return redirect(url_for('index', sort=sort))


@app.route('/update_category/<int:todo_id>', methods=['POST'])
def update_category(todo_id):
    category    = request.form.get('category')
    sort        = request.form.get('sort', 'category')
    valid_names = {c['name'] for c in load_categories()}
    if category in valid_names:
        todos = load_todos()
        if 0 <= todo_id < len(todos):
            todos[todo_id]['category'] = category
            save_todos(todos)
    return redirect(url_for('index', sort=sort))


@app.route('/update_notes/<int:todo_id>', methods=['POST'])
def update_notes(todo_id):
    notes = request.form.get('notes', '').strip()
    sort  = request.form.get('sort', 'category')
    todos = load_todos()
    if 0 <= todo_id < len(todos):
        todos[todo_id]['notes'] = notes
        save_todos(todos)
    return redirect(url_for('index', sort=sort))


@app.route('/update_parent/<int:todo_id>', methods=['POST'])
def update_parent(todo_id):
    parent_id_str = request.form.get('parent_id', '')
    sort          = request.form.get('sort', 'category')
    todos         = load_todos()
    if 0 <= todo_id < len(todos):
        if parent_id_str == '':
            todos[todo_id]['parent_id'] = None
        else:
            try:
                pid = int(parent_id_str)
                if 0 <= pid < len(todos) and pid != todo_id:
                    todos[todo_id]['parent_id'] = pid
            except ValueError:
                todos[todo_id]['parent_id'] = None
        save_todos(todos)
    return redirect(url_for('index', sort=sort))


# CATEGORY MANAGEMENT ROUTES

@app.route('/add_category', methods=['POST'])
def add_category():
    """Create a new user-defined category. Names are unique case-insensitively;
    a blank icon falls back to the default tag emoji."""
    name = request.form.get('category_name', '').strip()
    icon = request.form.get('category_icon', '').strip() or DEFAULT_ICON
    sort = request.form.get('sort', 'category')

    if name:
        cats     = load_categories()
        existing = {c['name'].lower() for c in cats}
        if name.lower() not in existing:
            # Insert before General so General stays the last, standing fallback
            others  = [c for c in cats if c['name'] != 'General']
            general = [c for c in cats if c['name'] == 'General']
            others.append({'name': name, 'icon': icon})
            save_categories(others + general)
    return redirect(url_for('index', sort=sort))


@app.route('/delete_category', methods=['POST'])
def delete_category():
    """Delete a user-created category and move its tasks to General.
    Built-in categories cannot be deleted."""
    name = request.form.get('category_name', '')
    sort = request.form.get('sort', 'category')

    if name and name not in DEFAULT_CATEGORY_NAMES:
        cats = [c for c in load_categories() if c['name'] != name]
        save_categories(cats)

        # Rehome any orphaned tasks so nothing is stranded on a missing category
        todos   = load_todos()
        changed = False
        for todo in todos:
            if todo.get('category') == name:
                todo['category'] = 'General'
                changed = True
        if changed:
            save_todos(todos)
    return redirect(url_for('index', sort=sort))


@app.route('/reorder', methods=['POST'])
def reorder():
    """Persist a new manual ordering after a drag-and-drop. Accepts JSON
    {'ids': [...]} listing the todo ids of one list in their new sequence."""
    data = request.get_json(silent=True) or {}
    ids  = data.get('ids', [])

    todos = load_todos()
    by_id = {t['id']: t for t in todos}
    for position, raw_id in enumerate(ids):
        try:
            tid = int(raw_id)
        except (ValueError, TypeError):
            continue
        if tid in by_id:
            by_id[tid]['order'] = position

    save_todos(todos)
    return jsonify({'status': 'ok'}), 200


@app.route('/delete/<int:todo_id>')
def delete_todo(todo_id):
    todos = load_todos()
    if 0 <= todo_id < len(todos):
        removed    = todos.pop(todo_id)
        removed_id = removed['id']

        if removed.get('done', False):
            stats = load_stats()
            stats['deleted_done_count'] = stats.get('deleted_done_count', 0) + 1
            save_stats(stats)

        # Unlink any children whose parent was just deleted
        for todo in todos:
            if todo.get('parent_id') == removed_id:
                todo['parent_id'] = None

        # Reassign sequential IDs and update any parent_id references
        old_to_new = {}
        for i, todo in enumerate(todos):
            old_to_new[todo['id']] = i
            todo['id'] = i
        for todo in todos:
            pid = todo.get('parent_id')
            if pid is not None:
                todo['parent_id'] = old_to_new.get(pid)

        save_todos(todos)
    return redirect(url_for('index'))


# API ENDPOINTS

@app.route('/api/todos', methods=['GET'])
def api_get_todos():
    return jsonify(load_todos()), 200


@app.route('/api/todos/<int:todo_id>', methods=['GET'])
def api_get_todo(todo_id):
    todos = load_todos()
    if 0 <= todo_id < len(todos):
        return jsonify(todos[todo_id]), 200
    return jsonify({'error': 'Todo not found'}), 404


@app.route('/api/todos', methods=['POST'])
def api_add_todo():
    data = request.get_json()
    if not data or 'task' not in data:
        return jsonify({'error': 'Task is required'}), 400

    todos    = load_todos()
    new_todo = {
        'task':      data['task'],
        'done':      data.get('done', False),
        'id':        len(todos),
        'category':  data.get('category', 'General'),
        'priority':  data.get('priority', 'Medium'),
        'notes':     data.get('notes', ''),
        'parent_id': data.get('parent_id', None),
        'order':     data.get('order', len(todos)),
    }
    todos.append(new_todo)
    save_todos(todos)
    return jsonify(new_todo), 201


@app.route('/api/todos/<int:todo_id>', methods=['PUT', 'PATCH'])
def api_update_todo(todo_id):
    todos = load_todos()
    if not (0 <= todo_id < len(todos)):
        return jsonify({'error': 'Todo not found'}), 404

    data = request.get_json()
    for field in ('task', 'done', 'category', 'priority', 'notes', 'parent_id', 'order'):
        if field in data:
            todos[todo_id][field] = data[field]

    save_todos(todos)
    return jsonify(todos[todo_id]), 200


@app.route('/api/todos/<int:todo_id>', methods=['DELETE'])
def api_delete_todo(todo_id):
    todos = load_todos()
    if not (0 <= todo_id < len(todos)):
        return jsonify({'error': 'Todo not found'}), 404

    deleted_todo = todos.pop(todo_id)
    removed_id   = deleted_todo['id']

    if deleted_todo.get('done', False):
        stats = load_stats()
        stats['deleted_done_count'] = stats.get('deleted_done_count', 0) + 1
        save_stats(stats)

    for todo in todos:
        if todo.get('parent_id') == removed_id:
            todo['parent_id'] = None

    old_to_new = {}
    for i, todo in enumerate(todos):
        old_to_new[todo['id']] = i
        todo['id'] = i
    for todo in todos:
        pid = todo.get('parent_id')
        if pid is not None:
            todo['parent_id'] = old_to_new.get(pid)

    save_todos(todos)
    return jsonify({'message': 'Todo deleted', 'todo': deleted_todo}), 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
