from flask import Flask, render_template, request, redirect, url_for, jsonify
import json
import os

app = Flask(__name__)

TODO_FILE  = '/app/data/todos.json'   # where we save todos (/app/data is volume mount point)
STATS_FILE = '/app/data/stats.json'   # persistent counters that survive task deletion


# STATS PERSISTENCE (survives task deletion)

def load_stats():
    """Load persistent stats from JSON file"""
    if os.path.exists(STATS_FILE):
        with open(STATS_FILE, 'r') as f:
            return json.load(f)
    return {'deleted_done_count': 0}   # default: no deleted completions yet


def save_stats(stats):
    """Save persistent stats to JSON file"""
    os.makedirs(os.path.dirname(STATS_FILE), exist_ok=True)
    with open(STATS_FILE, 'w') as f:
        json.dump(stats, f, indent=2)


# CATEGORY AND PRIORITY MANAGEMENT

def auto_assign_category(task):
    """Automatically assign category based on task keywords"""
    task_lower = task.lower()

    # Docker-related keywords
    if any(word in task_lower for word in ['docker', 'watchtower', 'wud', 'container']):
        return 'Docker'

    # HomeAssistant-related keywords
    if any(word in task_lower for word in ['homeassistant', 'home assistant', 'hacs', 'watchman', 'vscode extension']):
        return 'HomeAssistant'

    # Remote Access keywords
    if any(word in task_lower for word in ['remote', 'ssh', 'vpn', 'tailscale', 'access']):
        return 'Remote Access'

    # Scripting keywords
    if any(word in task_lower for word in ['script', 'api', 'flask', 'scriptable', 'cloud', 'sync']):
        return 'Scripting'

    # Monitoring keywords
    if any(word in task_lower for word in ['monitor', 'water', 'tracking', 'phpipam', 'phipam']):
        return 'Monitoring'

    # DBT keywords
    if any(word in task_lower for word in ['dbt', 'transform', 'staging', 'mart', 'data model', 'materialized']):
        return 'DBT'

    # HomeLab keywords
    if any(word in task_lower for word in ['homelab', 'home-lab', 'proxmox', 'truenas', 'rack', 'server rack']):
        return 'HomeLab'

    # AI keywords
    if any(word in task_lower for word in ['ai', 'llm', 'claude', 'openai', 'ollama', 'chatgpt', 'copilot', 'machine learning']):
        return 'AI'

    # House-Projects keywords
    if any(word in task_lower for word in ['house', 'renovation', 'yard', 'garden', 'furniture', 'repair', 'plumbing', 'electrical']):
        return 'House-Projects'

    # Default category
    return 'General'


def migrate_todos(todos):
    migrated = False
    for todo in todos:
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
    return todos, migrated


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

        # Pending-first sort within children
        children_sorted = sorted(children, key=lambda c: c['done'])

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

    # Sink done parent groups to the bottom
    return sorted(result, key=lambda item: item['todo']['done'])


def calculate_metrics(todos, stats=None):
    """Calculate metrics for the dashboard.

    completed and total both include tasks that were marked done then deleted,
    so the counters never drop when you clean up finished tasks.
    """
    if stats is None:
        stats = {'deleted_done_count': 0}

    deleted_done      = stats.get('deleted_done_count', 0)
    current_done      = sum(1 for todo in todos if todo['done'])
    current_pending   = sum(1 for todo in todos if not todo['done'])
    completed_tasks   = current_done + deleted_done          # all-time completions
    total_tasks       = len(todos) + deleted_done            # active + ever-completed-and-deleted
    completion_percentage = (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0
    high_priority_pending = sum(1 for todo in todos if not todo['done'] and todo.get('priority') == 'High')

    return {
        'total': total_tasks,
        'pending': current_pending,
        'completed': completed_tasks,
        'completion_percentage': round(completion_percentage, 1),
        'high_priority_pending': high_priority_pending
    }


#  Check to see if JSON file exists, if yes -> read and convert JSON to python list, if not -> empty string
def load_todos():
    """Load todos from JSON file and migrate if needed"""
    if os.path.exists(TODO_FILE):           # Does file exist?
        with open(TODO_FILE, 'r') as f:     # Open file for reading
            todos = json.load(f)            # Parse JSON -> Python list

        # Migrate old todos to new format with category/priority
        todos, migrated = migrate_todos(todos)
        if migrated:
            save_todos(todos)               # Save if migration occurred

        return todos
    return []                               # if no file, return empty list

# Make sure /data exists, Convert Python lisy to JSON, Writes files with pretty formatting
def save_todos(todos):
    """Save todos to JSON file"""
    os.makedirs(os.path.dirname(TODO_FILE), exist_ok=True)  # create /data if needed
    with open(TODO_FILE, 'w') as f:                         # Open for writing
        json.dump(todos, f, indent=2)                       # Convert list -> JSON


# ROUTES

# when someone visits localhost:5000/ -> Flask calls index() fx, Loads todos from JSON,
# calculates metrics, groups by category, and renders the page
@app.route('/')     # @ = decorator, '/' tells flask, when someone visits /, run this fx
def index():
    """Main page - shows all todos with metrics and category grouping"""
    todos = load_todos()                                # get todos from file
    stats = load_stats()                                # get persistent completion stats
    metrics = calculate_metrics(todos, stats)           # calculate dashboard metrics
    sort = request.args.get('sort', 'category')         # 'category' (default) or 'urgency'

    categories = ['Docker', 'HomeAssistant', 'Remote Access', 'Scripting', 'Monitoring', 'DBT', 'HomeLab', 'AI', 'House-Projects', 'General']

    grouped_todos = {}
    if sort == 'urgency':
        for priority in ['High', 'Medium', 'Low']:
            priority_todos = [t for t in todos if t.get('priority') == priority]
            if priority_todos:
                # Flat items wrapped in hierarchy shape for template consistency
                grouped_todos[priority] = [
                    {'todo': t, 'children': [], 'eligible_parents': [], 'is_parent': False}
                    for t in sorted(priority_todos, key=lambda t: t['done'])
                ]
    else:
        for category in categories:
            category_todos = [t for t in todos if t.get('category') == category]
            if category_todos:
                grouped_todos[category] = build_hierarchy(category_todos)

    return render_template('index.html',
                         todos=todos,
                         metrics=metrics,
                         grouped_todos=grouped_todos,
                         sort=sort,
                         categories=categories)


# User types task, selects category/priority & clicks add -> browser sends POST request to /add
# flask gets form data and creates new todo dictionary with all fields
@app.route('/add', methods=['POST'])
def add_todo():
    """Add a new todo with category and priority"""
    task = request.form.get('task')             # Get text from form input
    category = request.form.get('category', 'General')  # Get category (default: General)
    priority = request.form.get('priority', 'Medium')   # Get priority (default: Medium)

    if task:                                    # If they typed something
        todos = load_todos()                    # Load existing todos
        todos.append({
            'task':      task,
            'done':      False,
            'id':        len(todos),
            'category':  category,
            'priority':  priority,
            'notes':     '',
            'parent_id': None,
        })
        save_todos(todos)                       # Save updated list
    return redirect(url_for('index'))           # Go back to homepage

#You click "Done" button for todo, Browser goes to /toggle/2,
# Flask calls toggle_todo(2) - the 2 becomes todo_id, Gets todo at index 2: todos[2]
# Flips done: False → True (or vice versa), Saves and redirects
@app.route('/toggle/<int:todo_id>')
def toggle_todo(todo_id):
    """Mark a todo as done/undone"""
    todos = load_todos()                          # Load todos
    if 0 <= todo_id < len(todos):                 # Valid ID?
        todos[todo_id]['done'] = not todos[todo_id]['done']  # Flip True↔False
        save_todos(todos)                         # Save
    return redirect(url_for('index'))             # Back to homepage


# Update priority of a todo
@app.route('/update_priority/<int:todo_id>', methods=['POST'])
def update_priority(todo_id):
    """Update the priority of a todo"""
    priority = request.form.get('priority')
    sort = request.form.get('sort', 'category')   # preserve current sort view
    if priority in ['High', 'Medium', 'Low']:
        todos = load_todos()
        if 0 <= todo_id < len(todos):
            todos[todo_id]['priority'] = priority
            save_todos(todos)
    return redirect(url_for('index', sort=sort))


# Update category of a todo
@app.route('/update_category/<int:todo_id>', methods=['POST'])
def update_category(todo_id):
    """Update the category of a todo"""
    category = request.form.get('category')
    sort = request.form.get('sort', 'category')   # preserve current sort view
    valid_categories = ['Docker', 'HomeAssistant', 'Remote Access', 'Scripting', 'Monitoring',
                        'DBT', 'HomeLab', 'AI', 'House-Projects', 'General']
    if category in valid_categories:
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


# Click "Delete" on todo -> Goes to /delete/ -> Removes todo at index 1: todos.pop(1)
# Reassigns IDs so they're sequential again, Saves and redirects
@app.route('/delete/<int:todo_id>')
def delete_todo(todo_id):
    """Delete a todo. If it was marked done, persist that completion in stats
    so the completed counter never drops when cleaning up finished tasks."""
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


# API ENDPOINTS (for Scriptable widget and other apps)

@app.route('/api/todos', methods=['GET'])
def api_get_todos():
    """API endpoint to get all todos as JSON"""
    todos = load_todos()                    # Load todos from file
    return jsonify(todos), 200              # Return as JSON with 200 OK status


@app.route('/api/todos/<int:todo_id>', methods=['GET'])
def api_get_todo(todo_id):
    """API endpoint to get a single todo as JSON"""
    todos = load_todos()                    # Load todos
    if 0 <= todo_id < len(todos):           # Valid ID?
        return jsonify(todos[todo_id]), 200 # Return that todo as JSON
    return jsonify({'error': 'Todo not found'}), 404  # Not found error


@app.route('/api/todos', methods=['POST'])
def api_add_todo():
    """API endpoint to create a new todo with category and priority"""
    data = request.get_json()               # Get JSON data from request
    if not data or 'task' not in data:      # Check if task was provided
        return jsonify({'error': 'Task is required'}), 400

    todos = load_todos()                    # Load existing todos
    new_todo = {
        'task':      data['task'],
        'done':      data.get('done', False),
        'id':        len(todos),
        'category':  data.get('category', 'General'),
        'priority':  data.get('priority', 'Medium'),
        'notes':     data.get('notes', ''),
        'parent_id': data.get('parent_id', None),
    }
    todos.append(new_todo)                  # Add to list
    save_todos(todos)                       # Save
    return jsonify(new_todo), 201           # Return new todo with 201 Created


@app.route('/api/todos/<int:todo_id>', methods=['PUT', 'PATCH'])
def api_update_todo(todo_id):
    """API endpoint to update a todo (including category and priority)"""
    todos = load_todos()                    # Load todos
    if not (0 <= todo_id < len(todos)):     # Valid ID?
        return jsonify({'error': 'Todo not found'}), 404

    data = request.get_json()               # Get update data
    for field in ('task', 'done', 'category', 'priority', 'notes', 'parent_id'):
        if field in data:
            todos[todo_id][field] = data[field]

    save_todos(todos)                       # Save changes
    return jsonify(todos[todo_id]), 200     # Return updated todo


@app.route('/api/todos/<int:todo_id>', methods=['DELETE'])
def api_delete_todo(todo_id):
    """API endpoint to delete a todo"""
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


# Run Server
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
