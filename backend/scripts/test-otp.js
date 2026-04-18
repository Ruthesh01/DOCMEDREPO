'use strict';

const axios = require('axios');

async function testLogin() {
  try {
    console.log('Logging in...');
    const loginRes = await axios.post('http://localhost:5000/api/auth/login', {
      email: 'doctor@test.com',
      password: 'SecurePass123!',
      role: 'doctor'
    });
    console.log('Login response:', loginRes.data);
  } catch (err) {
    console.error('Login error:', err.response?.data || err.message);
  }
}

testLogin();
