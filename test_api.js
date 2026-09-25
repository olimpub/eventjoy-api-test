const jwt = require('jsonwebtoken');
const token = jwt.sign({ UserID: 356, email: 'test@eventjoy.hu' }, 'eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!', { expiresIn: '1h' });
const axios = require('axios');

axios.get('https://testapi.eventjoy.hu/api/event/data', {
    headers: { Authorization: `Bearer ${token}` }
}).then(res => console.log('SUCCESS:', res.status))
  .catch(err => {
      if (err.response) {
          console.log('ERROR STATUS:', err.response.status);
          console.log('ERROR DATA:', err.response.data);
      } else {
          console.log('NETWORK ERROR:', err.message);
      }
  });
