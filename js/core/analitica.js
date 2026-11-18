/* Analítica (GA4): helper único pmTrack + exclusión de visitas propias.
 * Nunca mandar datos personales (nombre, teléfono, dirección, notas) a GA.
 * Si el navegador bloquea GA (ad blockers) o hay un error, no pasa nada. */
(function () {
  'use strict';

  var CLAVE_NO_MEDIR = 'pm_no_medir';
  var unaVez = Object.create(null);

  // true si este navegador está marcado como "visitas propias" (dueño/admin)
  function pmMedicionApagada() {
    try { return window.localStorage.getItem(CLAVE_NO_MEDIR) === '1'; } catch (e) { return false; }
  }

  // Mete sucursal/modalidad si main.js los publica (window.pmContextoAnalitica)
  function contexto() {
    try {
      var fn = window.pmContextoAnalitica;
      return typeof fn === 'function' ? (fn() || {}) : {};
    } catch (e) { return {}; }
  }

  function pmTrack(nombre, params) {
    try {
      if (!nombre || pmMedicionApagada() || typeof window.gtag !== 'function') return false;
      var datos = Object.assign({}, contexto(), params || {});
      Object.keys(datos).forEach(function (k) {
        if (datos[k] === undefined || datos[k] === null || datos[k] === '') delete datos[k];
      });
      window.gtag('event', nombre, datos);
      return true;
    } catch (e) { return false; }
  }

  // Dispara el evento una sola vez por visita para esa clave
  function pmTrackUnaVez(clave, nombre, params) {
    try {
      var k = String(clave || nombre);
      if (unaVez[k]) return false;
      unaVez[k] = true;
      return pmTrack(nombre, params);
    } catch (e) { return false; }
  }

  window.pmMedicionApagada = pmMedicionApagada;
  window.pmTrack = pmTrack;
  window.pmTrackUnaVez = pmTrackUnaVez;
})();
