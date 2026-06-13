const BASE_URL = 'http://localhost:8000';

function getToken() {
  return localStorage.getItem('admin_token');
}

function logout() {
  localStorage.removeItem('admin_token');
  window.location.href = 'index.html';
}

async function login() {
  const username = document.getElementById('username').value.trim();
  const password = document.getElementById('password').value;
  const btn = document.getElementById('loginBtn');
  const error = document.getElementById('error');

  error.style.display = 'none';
  btn.disabled = true;
  btn.textContent = 'Signing in...';

  try {
    const res = await fetch(`${BASE_URL}/admin/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Login failed');
    localStorage.setItem('admin_token', data.access_token);
    window.location.href = 'dashboard.html';
  } catch (e) {
    error.textContent = e.message;
    error.style.display = 'block';
  } finally {
    btn.disabled = false;
    btn.textContent = 'Sign In';
  }
}

async function fetchListeners() {
  const tbody = document.getElementById('listenerTable');
  try {
    const res = await fetch(`${BASE_URL}/admin/listeners`, {
      headers: { 'Authorization': `Bearer ${getToken()}` },
    });
    if (res.status === 401 || res.status === 403) {
      logout();
      return;
    }
    const data = await res.json();
    renderTable(data.listeners);
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="4" class="empty">Failed to load listeners</td></tr>`;
  }
}

function renderTable(listeners) {
  const tbody = document.getElementById('listenerTable');
  if (listeners.length === 0) {
    tbody.innerHTML = `<tr><td colspan="4" class="empty">No listeners yet</td></tr>`;
    return;
  }
  tbody.innerHTML = listeners.map(l => `
    <tr id="row-${l.username}">
      <td>${l.username}</td>
      <td><span class="badge ${l.is_online ? 'online' : 'offline'}">${l.is_online ? 'Online' : 'Offline'}</span></td>
      <td>${new Date(l.created_at).toLocaleDateString()}</td>
      <td><button class="btn-delete" onclick="deleteListener('${l.username}')">Delete</button></td>
    </tr>
  `).join('');
}

async function createListener() {
  const username = document.getElementById('newUsername').value.trim();
  const password = document.getElementById('newPassword').value;
  const btn = document.getElementById('createBtn');
  const feedback = document.getElementById('createFeedback');

  feedback.style.display = 'none';
  feedback.className = 'feedback';

  if (!username || !password) {
    feedback.textContent = 'Username and password are required';
    feedback.classList.add('error');
    feedback.style.display = 'block';
    return;
  }

  btn.disabled = true;
  btn.textContent = 'Creating...';

  try {
    const res = await fetch(`${BASE_URL}/admin/listener`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${getToken()}`,
      },
      body: JSON.stringify({ username, password }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Failed to create listener');
    feedback.textContent = `Listener "${username}" created successfully`;
    feedback.classList.add('success');
    feedback.style.display = 'block';
    document.getElementById('newUsername').value = '';
    document.getElementById('newPassword').value = '';
    fetchListeners();
  } catch (e) {
    feedback.textContent = e.message;
    feedback.classList.add('error');
    feedback.style.display = 'block';
  } finally {
    btn.disabled = false;
    btn.textContent = 'Create';
  }
}

async function deleteListener(username) {
  if (!confirm(`Delete listener "${username}"?`)) return;
  try {
    const res = await fetch(`${BASE_URL}/admin/listener/${username}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${getToken()}` },
    });
    if (!res.ok) {
      const data = await res.json();
      throw new Error(data.detail || 'Failed to delete');
    }
    document.getElementById(`row-${username}`)?.remove();
    const tbody = document.getElementById('listenerTable');
    if (tbody.children.length === 0) {
      tbody.innerHTML = `<tr><td colspan="4" class="empty">No listeners yet</td></tr>`;
    }
  } catch (e) {
    alert(e.message);
  }
}

async function loadCoinRate() {
  try {
    const res = await fetch(`${BASE_URL}/coins/rate`, {
      headers: { Authorization: 'Bearer ' + getToken() }
    });
    const data = await res.json();
    document.getElementById('coinRate').value = data.coins_per_minute;
  } catch (e) {}
}

async function saveCoinRate() {
  const value = parseFloat(document.getElementById('coinRate').value);
  const feedback = document.getElementById('coinRateFeedback');
  const btn = document.getElementById('coinRateBtn');

  if (!value || value <= 0) {
    feedback.textContent = 'Enter a valid rate';
    feedback.className = 'feedback error';
    feedback.style.display = 'block';
    return;
  }

  btn.disabled = true;
  try {
    const res = await fetch(`${BASE_URL}/coins/admin/rate`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + getToken(),
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ coins_per_minute: value })
    });
    feedback.textContent = res.ok ? 'Rate saved successfully' : 'Failed to save rate';
    feedback.className = 'feedback ' + (res.ok ? 'success' : 'error');
  } catch (e) {
    feedback.textContent = 'Network error';
    feedback.className = 'feedback error';
  } finally {
    feedback.style.display = 'block';
    btn.disabled = false;
  }
}

async function addCoins() {
  const username = document.getElementById('coinUsername').value.trim();
  const amount = parseFloat(document.getElementById('coinAmount').value);
  const feedback = document.getElementById('coinFeedback');
  const btn = document.getElementById('addCoinsBtn');

  if (!username || !amount || amount <= 0) {
    feedback.textContent = 'Enter a valid username and amount';
    feedback.className = 'feedback error';
    feedback.style.display = 'block';
    return;
  }

  btn.disabled = true;
  try {
    const res = await fetch(`${BASE_URL}/coins/admin/add`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + getToken(),
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ username, amount })
    });
    const data = await res.json();
    feedback.textContent = res.ok
      ? `Added ${amount} coins to ${username}. New balance: ${data.new_balance}`
      : data.detail || 'Failed to add coins';
    feedback.className = 'feedback ' + (res.ok ? 'success' : 'error');
  } catch (e) {
    feedback.textContent = 'Network error';
    feedback.className = 'feedback error';
  } finally {
    feedback.style.display = 'block';
    btn.disabled = false;
  }
}

if (window.location.pathname.includes('dashboard')) {
  if (!getToken()) {
    window.location.href = 'index.html';
  } else {
    fetchListeners();
    loadCoinRate();
  }
}

document.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    if (window.location.pathname.includes('dashboard')) {
      createListener();
    } else {
      login();
    }
  }
});