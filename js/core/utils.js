/* ===== Piedra Mora - utilidades compartidas (Fase 0) ===== */
(function (window) {
  'use strict';

  const PM = window.PM = window.PM || {};

  function hoyArgentina() {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Argentina/Buenos_Aires',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(new Date());
  }

  function escaparHtml(valor) {
    return String(valor == null ? '' : valor).replace(/[&<>"']/g, (caracter) => {
      switch (caracter) {
        case '&': return '&amp;';
        case '<': return '&lt;';
        case '>': return '&gt;';
        case '"': return '&quot;';
        case "'": return '&#39;';
        default: return caracter;
      }
    });
  }

  function esRutaImagenSegura(valor) {
    const ruta = String(valor || '').trim();
    if (!ruta) return false;
    if (/['"\\\n\r]/.test(ruta)) return false;
    if (/^data:image\/(png|jpe?g|webp|avif|gif);base64,/i.test(ruta)) return true;
    if (/^https?:\/\//i.test(ruta)) return true;
    if (/^\/\//.test(ruta)) return true;
    if (/^[a-z][a-z0-9+.-]*:/i.test(ruta)) return false;
    return true;
  }

  function urlImagenSegura(valor, fallback) {
    return esRutaImagenSegura(valor) ? String(valor).trim() : fallback;
  }

  function urlExternaSegura(valor, fallback) {
    const ruta = String(valor || '').trim();
    return /^https?:\/\//i.test(ruta) ? ruta : fallback;
  }

  const OFFSET_OFERTA_AR = '-03:00';

  function parseFechaOferta(valor) {
    const texto = String(valor == null ? '' : valor).trim();
    if (!texto) return null;

    let normalizado = texto;
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/.test(texto)) {
      normalizado = texto + (texto.length === 16 ? ':00' : '') + OFFSET_OFERTA_AR;
    }

    const ms = Date.parse(normalizado);
    return Number.isFinite(ms) ? ms : null;
  }

  function ofertaVigente(producto, ahoraMs) {
    if (!producto) return false;

    const ahora = Number.isFinite(ahoraMs) ? ahoraMs : Date.now();

    if (producto.oferta_desde) {
      const desde = parseFechaOferta(producto.oferta_desde);
      if (desde !== null && ahora < desde) return false;
    }

    if (producto.oferta_hasta) {
      const hasta = parseFechaOferta(producto.oferta_hasta);
      if (hasta !== null && ahora > hasta) return false;
    }

    return true;
  }

  function fechaOfertaCorta(valor) {
    const ms = parseFechaOferta(valor);
    if (ms === null) return '';

    const partes = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Argentina/Buenos_Aires',
      day: '2-digit',
      month: '2-digit'
    }).formatToParts(new Date(ms));

    const obtener = (tipo) => {
      const parte = partes.find(item => item.type === tipo);
      return parte ? parte.value : '';
    };

    return `${obtener('day')}/${obtener('month')}`;
  }

  function fechaOfertaLarga(valor) {
    const ms = parseFechaOferta(valor);
    if (ms === null) return '';

    const partes = new Intl.DateTimeFormat('es-AR', {
      timeZone: 'America/Argentina/Buenos_Aires',
      weekday: 'long',
      day: '2-digit',
      month: '2-digit'
    }).formatToParts(new Date(ms));

    const obtener = (tipo) => {
      const parte = partes.find(item => item.type === tipo);
      return parte ? parte.value : '';
    };

    const dia = Number(obtener('day')) || obtener('day');
    return `${obtener('weekday')} ${dia}/${obtener('month')}`;
  }

  function horaOfertaCorta(valor) {
    const ms = parseFechaOferta(valor);
    if (ms === null) return '';

    const partes = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'America/Argentina/Buenos_Aires',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    }).formatToParts(new Date(ms));

    const obtener = (tipo) => {
      const parte = partes.find(item => item.type === tipo);
      return parte ? parte.value : '';
    };

    return `${obtener('hour')}:${obtener('minute')}`;
  }

  function fechaOfertaParaInput(valor) {
    const ms = parseFechaOferta(valor);
    if (ms === null) return '';

    const partes = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Argentina/Buenos_Aires',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    }).formatToParts(new Date(ms));

    const obtener = (tipo) => {
      const parte = partes.find(item => item.type === tipo);
      return parte ? parte.value : '';
    };

    return `${obtener('year')}-${obtener('month')}-${obtener('day')}T${obtener('hour')}:${obtener('minute')}`;
  }

  function inputOfertaAIso(valor) {
    const texto = String(valor == null ? '' : valor).trim();
    if (!texto) return '';

    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(texto)) return '';
    if (parseFechaOferta(texto) === null) return '';

    return `${texto}:00${OFFSET_OFERTA_AR}`;
  }

  function productoEstaAgotado(producto, fechaHoy) {
    if (!producto || producto.agotado !== true) return false;
    if (producto.agotado_hasta_nuevo_aviso === true) return true;
    return producto.agotado_fecha === (fechaHoy || hoyArgentina());
  }

  function normalizarAgotado(producto, fechaHoy) {
    if (!producto || typeof producto !== 'object') return producto;

    const hoy = fechaHoy || hoyArgentina();

    if (producto.agotado !== true) {
      producto.agotado = false;
      producto.agotado_fecha = null;
      producto.agotado_hasta_nuevo_aviso = false;
      return producto;
    }

    if (producto.agotado_hasta_nuevo_aviso === true) {
      producto.agotado = true;
      if (!producto.agotado_fecha) producto.agotado_fecha = hoy;
      return producto;
    }

    if (producto.agotado_fecha !== hoy) {
      producto.agotado = false;
      producto.agotado_fecha = null;
      producto.agotado_hasta_nuevo_aviso = false;
    }

    return producto;
  }

  // Teléfonos argentinos: 10 dígitos (área + número), sin 0, 15, 54 ni 9.
  // Misma regla que public.pm_normalizar_telefono (migración 023). Devuelve null si no da 10 dígitos.
  function normalizarTelefonoAR(valor) {
    let v = String(valor == null ? '' : valor).replace(/\D/g, '');
    if (v.startsWith('54') && v.length > 10) v = v.slice(2);
    if (v.length === 11 && v.startsWith('9')) v = v.slice(1);
    if (v.startsWith('0')) v = v.slice(1);
    if (v.length === 12) {
      if (v.slice(0, 2) === '11' && v.slice(2, 4) === '15') v = v.slice(0, 2) + v.slice(4);
      else if (v.slice(3, 5) === '15') v = v.slice(0, 3) + v.slice(5);
      else if (v.slice(4, 6) === '15') v = v.slice(0, 4) + v.slice(6);
    }
    return /^[0-9]{10}$/.test(v) ? v : null;
  }

  // 3834818271 -> "383 481-8271" (11 -> "11 4567-8901"). Si no se puede normalizar, devuelve el valor original.
  function formatearTelefonoAR(valor) {
    const n = normalizarTelefonoAR(valor);
    if (!n) return String(valor == null ? '' : valor);
    return n.startsWith('11')
      ? `${n.slice(0, 2)} ${n.slice(2, 6)}-${n.slice(6)}`
      : `${n.slice(0, 3)} ${n.slice(3, 6)}-${n.slice(6)}`;
  }

  // wa.me con 549 + 10 dígitos. Si es un dato viejo que no se puede normalizar, usa solo sus dígitos; vacío si no hay.
  function urlWhatsappCliente(valor) {
    const n = normalizarTelefonoAR(valor);
    if (n) return `https://wa.me/549${n}`;
    const d = String(valor == null ? '' : valor).replace(/\D/g, '');
    return d ? `https://wa.me/${d}` : '';
  }

  PM.normalizarTelefonoAR = normalizarTelefonoAR;
  PM.formatearTelefonoAR = formatearTelefonoAR;
  PM.urlWhatsappCliente = urlWhatsappCliente;
  PM.hoyArgentina = hoyArgentina;
  PM.escaparHtml = escaparHtml;
  PM.esRutaImagenSegura = esRutaImagenSegura;
  PM.urlImagenSegura = urlImagenSegura;
  PM.urlExternaSegura = urlExternaSegura;
  PM.productoEstaAgotado = productoEstaAgotado;
  PM.normalizarAgotado = normalizarAgotado;
  PM.parseFechaOferta = parseFechaOferta;
  PM.ofertaVigente = ofertaVigente;
  PM.fechaOfertaCorta = fechaOfertaCorta;
  PM.fechaOfertaLarga = fechaOfertaLarga;
  PM.horaOfertaCorta = horaOfertaCorta;
  PM.fechaOfertaParaInput = fechaOfertaParaInput;
  PM.inputOfertaAIso = inputOfertaAIso;
})(window);
