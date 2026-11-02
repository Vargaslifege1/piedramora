/* ===== Íconos reutilizables para los botones de pedido ===== */

const ICONOS = {
  whatsapp: `<svg class="icono-btn" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12.04 2C6.58 2 2.13 6.45 2.13 11.91c0 1.75.46 3.45 1.32 4.95L2.05 22l5.25-1.38a9.9 9.9 0 0 0 4.74 1.21h.01c5.46 0 9.9-4.45 9.9-9.9 0-2.65-1.03-5.14-2.9-7.01A9.87 9.87 0 0 0 12.04 2Zm0 18.12h-.01a8.2 8.2 0 0 1-4.19-1.15l-.3-.18-3.12.82.83-3.04-.2-.31a8.22 8.22 0 0 1-1.26-4.39c0-4.54 3.7-8.24 8.25-8.24 2.2 0 4.27.86 5.83 2.42a8.18 8.18 0 0 1 2.41 5.83c0 4.55-3.7 8.24-8.24 8.24Zm4.52-6.17c-.25-.12-1.46-.72-1.69-.8-.23-.08-.39-.12-.56.13-.17.24-.64.8-.78.96-.14.17-.29.19-.53.06-.25-.12-1.04-.38-1.98-1.22-.73-.65-1.23-1.46-1.37-1.7-.14-.25-.02-.38.11-.5.11-.11.25-.29.37-.43.12-.15.16-.25.24-.42.08-.17.04-.31-.02-.43-.06-.12-.56-1.35-.77-1.85-.2-.48-.41-.42-.56-.43h-.48c-.17 0-.43.06-.66.31-.23.24-.86.85-.86 2.06 0 1.22.88 2.4 1 2.56.12.17 1.74 2.66 4.22 3.73.59.25 1.05.4 1.41.52.59.19 1.13.16 1.55.1.47-.07 1.46-.6 1.67-1.17.2-.58.2-1.08.14-1.18-.06-.1-.22-.16-.47-.28Z" />
    </svg>`,
  telefono: `<svg class="icono-btn" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13 1 .36 1.98.68 2.92a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.16-1.16a2 2 0 0 1 2.11-.45c.94.32 1.92.55 2.92.68A2 2 0 0 1 22 16.92Z" />
    </svg>`,
  pedix: `<svg class="icono-btn" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <rect x="3" y="8" width="18" height="12" rx="2" />
      <path d="M8 8V6a4 4 0 0 1 8 0v2" />
      <path d="M8 12h8" />
    </svg>`,
  pedidosya: `<svg class="icono-btn" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M3 3h2l.4 2M7 13h10l4-8H5.4" />
      <circle cx="9" cy="21" r="1.5" />
      <circle cx="18" cy="21" r="1.5" />
    </svg>`,
  maps: `<svg class="icono-btn" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" />
      <circle cx="12" cy="10" r="3" />
    </svg>`
};

const ICONO_ESTRELLA = `<svg class="icono-mini" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M12 2.5l2.9 6.06 6.6.82-4.87 4.6 1.27 6.6L12 17.5l-5.9 3.08 1.27-6.6-4.87-4.6 6.6-.82L12 2.5z" />
  </svg>`;

const ICONO_UBICACION = `<svg class="icono-info" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z" />
    <circle cx="12" cy="10" r="3" />
  </svg>`;

const ICONO_RELOJ = `<svg class="icono-info" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <circle cx="12" cy="12" r="9" />
    <path d="M12 7v5l3.5 2" />
  </svg>`;

const ICONO_PUNTO = `<svg class="icono-punto" viewBox="0 0 8 8" aria-hidden="true"><circle cx="4" cy="4" r="4" /></svg>`;


/* ===== Tracking de clics (Google Analytics) ===== */

function trackearClic(tipoBoton, sucursal) {
  if (typeof gtag === 'function' && sucursal) {
    gtag('event', 'click_boton_pedido', {
      tipo_boton: tipoBoton,
      sucursal_id: sucursal.id,
      sucursal_nombre: sucursal.nombre
    });
  }
}

function trackearClicCarta(tipoBoton, sucursalId, sucursalNombre, extra = {}) {
  if (typeof gtag === 'function') {
    gtag('event', 'click_boton_pedido', {
      tipo_boton: tipoBoton,
      sucursal_id: sucursalId,
      sucursal_nombre: sucursalNombre,
      ...extra
    });
  }
}

function atributoTracking(tipoBoton, sucursal) {
  return `onclick="trackearClic('${tipoBoton}', SUCURSALES['${sucursal.id}'])"`;
}


/* ===== Generación de un botón de pedido ===== */

function crearBoton({ href, clase = '', icono, texto, tracking }) {
  return `
    <a href="${href}" target="_blank" rel="noopener noreferrer" class="btn-pedido ${clase}" ${tracking}>
      ${icono}
      <span>${texto}</span>
    </a>`;
}

function crearBotonesPedido(botones, sucursal) {
  const piezas = [];

  if (botones.whatsapp) {
    piezas.push(crearBoton({
      href: `https://wa.me/${botones.whatsapp}?text=Hola!%20Quiero%20hacer%20un%20pedido`,
      clase: 'btn-whatsapp',
      icono: ICONOS.whatsapp,
      texto: 'Pedir por WhatsApp',
      tracking: atributoTracking('whatsapp', sucursal)
    }));
  }

  if (botones.pedix) {
    piezas.push(crearBoton({
      href: botones.pedix,
      icono: ICONOS.pedix,
      texto: 'Pedir por Pedix',
      tracking: atributoTracking('pedix', sucursal)
    }));
  }

  if (botones.telefono) {
    piezas.push(`
      <a href="tel:${botones.telefono}" class="btn-pedido" ${atributoTracking('telefono', sucursal)}>
        ${ICONOS.telefono}
        <span>Llamar por teléfono</span>
      </a>`);
  }

  if (botones.pedidosya) {
    piezas.push(crearBoton({
      href: botones.pedidosya,
      icono: ICONOS.pedidosya,
      texto: 'Pedir por PedidosYa',
      tracking: atributoTracking('pedidosya', sucursal)
    }));
  }

  return piezas.join('');
}


/* ===== Carta: datos y utilidades ===== */
let SUCURSALES = {};
let CARTAS_POR_SUCURSAL = {};
let CARTA_CACHE_LOADED = false;
let cartaCargaPromise = null;

function formatearPrecioAR(valor) {
  try {
    return new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS', maximumFractionDigits: 0 }).format(Number(valor) || 0);
  } catch (e) {
    return `$${valor}`;
  }
}

function cargarCartasEnSegundoPlano() {
  if (CARTA_CACHE_LOADED) return Promise.resolve(CARTAS_POR_SUCURSAL);
  if (cartaCargaPromise) return cartaCargaPromise;
  cartaCargaPromise = fetch('data/cartas.json')
    .then(resp => {
      if (!resp.ok) throw new Error('No se pudo cargar cartas.json');
      return resp.json();
    })
    .then(datos => {
      CARTAS_POR_SUCURSAL = datos.cartasPorSucursal || {};
      CARTA_CACHE_LOADED = true;
      return CARTAS_POR_SUCURSAL;
    })
    .catch(error => {
      console.error(error);
      CARTAS_POR_SUCURSAL = {};
      CARTA_CACHE_LOADED = true;
      return CARTAS_POR_SUCURSAL;
    });
  return cartaCargaPromise;
}

function precargarCartas() {
  cargarCartasEnSegundoPlano();
}


/* ===== Generación de una tarjeta de sucursal ===== */
function crearTarjetaSucursal(sucursal) {
  const urlMaps = `https://www.google.com/maps/search/?api=1&query=${sucursal.lat},${sucursal.lng}`;

  return `
    <div class="sucursal-card reveal" data-sucursal="${sucursal.id}" data-lat="${sucursal.lat}" data-lng="${sucursal.lng}">
      <span class="badge-cercana" hidden>
        ${ICONO_ESTRELLA}
        MÁS CERCA DE VOS
      </span>

      <div class="sucursal-foto-wrap">
        <img src="${sucursal.foto}" alt="Sucursal ${sucursal.nombre}" class="sucursal-foto" loading="lazy" decoding="async">
        <div class="sucursal-foto-degradado"></div>
        <div class="sucursal-foto-titulo">
          <h3>${sucursal.nombre}</h3>
          <span class="estado-badge" data-estado aria-live="polite">
            ${ICONO_PUNTO}
            <span data-estado-texto>...</span>
          </span>
        </div>
      </div>

      <div class="sucursal-info">
        <p class="sucursal-direccion">
          ${ICONO_UBICACION}
          ${sucursal.direccion}
        </p>

        <p class="sucursal-horario">
          ${ICONO_RELOJ}
          ${sucursal.horarioTexto}
        </p>

        <p class="sucursal-distancia" data-distancia hidden>
          ${ICONO_UBICACION}
          <span data-distancia-texto></span>
        </p>

        <div class="botones-pedido">
          <button type="button" class="btn-pedido btn-ver-carta" data-accion="ver-carta" data-sucursal-id="${sucursal.id}">Ver carta</button>
          ${crearBotonesPedido(sucursal.botones, sucursal)}
          <a href="${urlMaps}" target="_blank" rel="noopener noreferrer" class="btn-pedido btn-maps" ${atributoTracking('maps', sucursal)}>
            ${ICONOS.maps}
            <span>Abrir en Google Maps</span>
          </a>
        </div>
      </div>
    </div>`;
}


/* ===== Carga de datos y render inicial ===== */

async function cargarSucursales() {
  const contenedor = document.getElementById('sucursales-lista');

  try {
    const respuesta = await fetch('data/sucursales.json');
    if (!respuesta.ok) throw new Error('No se pudo cargar sucursales.json');
    const datos = await respuesta.json();

    contenedor.innerHTML = datos.sucursales.map(crearTarjetaSucursal).join('');

    datos.sucursales.forEach((s) => {
      SUCURSALES[s.id] = s;
    });

    inicializarAnimacionesReveal();
    actualizarEstados();
    setInterval(actualizarEstados, 60 * 1000);
    pedirUbicacion();

    cargarCartasEnSegundoPlano();
    setTimeout(abrirDesdeHash, 50);
  } catch (error) {
    contenedor.innerHTML = '<p style="color:#a8a8a8;text-align:center;">No se pudieron cargar las sucursales. Probá recargar la página.</p>';
    console.error(error);
  }
}


/* ===== Animación de aparición al hacer scroll ===== */

function inicializarAnimacionesReveal() {
  const elementosParaAnimar = document.querySelectorAll('.reveal');

  const observador = new IntersectionObserver((entradas) => {
    entradas.forEach((entrada) => {
      if (entrada.isIntersecting) {
        entrada.target.classList.add('visible');
      } else {
        entrada.target.classList.remove('visible');
      }
    });
  }, {
    threshold: 0.2
  });

  elementosParaAnimar.forEach((el) => observador.observe(el));
}


/* ===== Horarios de apertura por sucursal ===== */

function minutosDesdeMedianoche(hora, minuto) {
  return hora * 60 + minuto;
}

function estaAbiertoAhora(sucursal) {
  const h = sucursal.horarios;
  const ahora = new Date();
  const diaDeHoy = ahora.getDay();
  const minutosAhora = minutosDesdeMedianoche(ahora.getHours(), ahora.getMinutes());

  const apertura = minutosDesdeMedianoche(h.apertura.hora, h.apertura.minuto);

  function cierreSegunDia(dia) {
    const esFinde = dia === 5 || dia === 6;
    const cierre = esFinde ? h.cierreFinde : h.cierreNormal;
    return minutosDesdeMedianoche(cierre.hora, cierre.minuto);
  }

  if (minutosAhora >= apertura) {
    if (diaDeHoy === 1 && h.cerradoLunes) return false;
    return true;
  }

  const diaDeAyer = (diaDeHoy + 6) % 7;
  const cierreDeAyer = cierreSegunDia(diaDeAyer);

  if (minutosAhora < cierreDeAyer) {
    if (diaDeAyer === 1 && h.cerradoLunes) return false;
    return true;
  }

  return false;
}

function actualizarEstados() {
  document.querySelectorAll('.sucursal-card').forEach((tarjeta) => {
    const id = tarjeta.dataset.sucursal;
    const sucursal = SUCURSALES[id];
    if (!sucursal) return;

    const badge = tarjeta.querySelector('[data-estado]');
    if (!badge) return;
    const textoEstado = badge.querySelector('[data-estado-texto]');
    const abierto = estaAbiertoAhora(sucursal);

    if (abierto) {
      textoEstado.textContent = 'Abierto ahora';
      badge.classList.add('abierto');
      badge.classList.remove('cerrado');
    } else {
      textoEstado.textContent = 'Cerrado';
      badge.classList.add('cerrado');
      badge.classList.remove('abierto');
    }
  });
}


/* ===== Distancia del usuario a cada sucursal ===== */

function calcularDistanciaKm(lat1, lng1, lat2, lng2) {
  const radioTierraKm = 6371;
  const gradosARadianes = (grados) => grados * (Math.PI / 180);

  const diferenciaLat = gradosARadianes(lat2 - lat1);
  const diferenciaLng = gradosARadianes(lng2 - lng1);

  const a =
    Math.sin(diferenciaLat / 2) * Math.sin(diferenciaLat / 2) +
    Math.cos(gradosARadianes(lat1)) *
      Math.cos(gradosARadianes(lat2)) *
      Math.sin(diferenciaLng / 2) *
      Math.sin(diferenciaLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return radioTierraKm * c;
}

function mostrarToastCercania(tarjetaCercana) {
  const toast = document.getElementById('toast-ubicacion');
  if (!toast) return;

  toast.textContent = 'Encontramos la sucursal más cercana para vos';
  toast.hidden = false;

  requestAnimationFrame(() => toast.classList.add('visible'));

  tarjetaCercana.classList.add('destacada');

  setTimeout(() => {
    toast.classList.remove('visible');
    tarjetaCercana.classList.remove('destacada');
  }, 1600);

  setTimeout(() => {
    toast.hidden = true;
  }, 2000);
}

function mostrarDistancias(latUsuario, lngUsuario) {
  const contenedor = document.getElementById('sucursales-lista');
  const tarjetas = Array.from(contenedor.querySelectorAll('.sucursal-card'));

  const tarjetasConDistancia = tarjetas.map((tarjeta) => {
    const lat = parseFloat(tarjeta.dataset.lat);
    const lng = parseFloat(tarjeta.dataset.lng);
    const distancia = calcularDistanciaKm(latUsuario, lngUsuario, lat, lng);
    return { tarjeta, distancia };
  });

  tarjetasConDistancia.forEach(({ tarjeta, distancia }) => {
    const elementoDistancia = tarjeta.querySelector('[data-distancia]');
    if (!elementoDistancia) return;
    const textoDistancia = elementoDistancia.querySelector('[data-distancia-texto]');
    if (!textoDistancia) return;
    textoDistancia.textContent = `A ${distancia.toFixed(1).replace('.', ',')} km de vos`;
    elementoDistancia.hidden = false;
  });

  tarjetasConDistancia.sort((a, b) => a.distancia - b.distancia);

  const posicionesAntes = new Map();
  tarjetas.forEach((tarjeta) => {
    posicionesAntes.set(tarjeta, tarjeta.getBoundingClientRect());
  });

  tarjetasConDistancia.forEach(({ tarjeta }) => {
    contenedor.appendChild(tarjeta);
  });

  tarjetas.forEach((tarjeta) => {
    const b = tarjeta.querySelector('.badge-cercana');
    if (b) b.hidden = true;
  });
  if (tarjetasConDistancia[0]) {
    const tarjetaMasCercana = tarjetasConDistancia[0].tarjeta;
    const bc = tarjetaMasCercana.querySelector('.badge-cercana');
    if (bc) bc.hidden = false;

    tarjetas.forEach((tarjeta) => {
      const posicionAntes = posicionesAntes.get(tarjeta);
      if (!posicionAntes) return;
      const posicionDespues = tarjeta.getBoundingClientRect();

      const diferenciaX = posicionAntes.left - posicionDespues.left;
      const diferenciaY = posicionAntes.top - posicionDespues.top;

      if (diferenciaX || diferenciaY) {
        tarjeta.style.transition = 'none';
        tarjeta.style.transform = `translate(${diferenciaX}px, ${diferenciaY}px)`;

        requestAnimationFrame(() => {
          tarjeta.style.transition = 'transform 0.6s ease';
          tarjeta.style.transform = '';
        });
      }
    });

    mostrarToastCercania(tarjetaMasCercana);
  }
}

function pedirUbicacion() {
  if (!navigator.geolocation) return;

  navigator.geolocation.getCurrentPosition(
    (posicion) => {
      mostrarDistancias(posicion.coords.latitude, posicion.coords.longitude);
    },
    () => {
      // Sin permiso
    }
  );
}


/* ===== Navbar con blur al hacer scroll ===== */

const navbar = document.querySelector('.navbar');
if (navbar) {
  window.addEventListener('scroll', () => {
    if (window.scrollY > 40) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  });
}


/* ===== MODAL DE CARTA ===== */
const cartaOverlay = document.getElementById('carta-overlay');
const cartaPanel = document.getElementById('carta-panel');
const cartaCerrar = document.getElementById('carta-cerrar');
const cartaTituloSucursal = document.getElementById('carta-titulo-sucursal');
const cartaTituloCarta = document.getElementById('carta-titulo-carta');
const cartaSelector = document.getElementById('carta-selector');
const cartaSelectorOpciones = document.getElementById('carta-selector-opciones');
const cartaContenido = document.getElementById('carta-contenido');
const cartaChips = document.getElementById('carta-chips');
const cartaCategorias = document.getElementById('carta-categorias');
const cartaActualizadoFecha = document.getElementById('carta-actualizado-fecha');
const cartaWhatsappWrap = document.getElementById('carta-whatsapp-wrap');
const cartaWhatsapp = document.getElementById('carta-whatsapp');

let cartaAbierta = false;
let ultimoFoco = null;
let scrollYActual = 0;
let observerCategorias = null;

function bloquearScrollFondo() {
  scrollYActual = window.scrollY || document.documentElement.scrollTop;
  document.body.style.position = 'fixed';
  document.body.style.top = `-${scrollYActual}px`;
  document.body.style.left = '0';
  document.body.style.right = '0';
  document.body.style.width = '100%';
}

function desbloquearScrollFondo() {
  document.body.style.position = '';
  document.body.style.top = '';
  document.body.style.left = '';
  document.body.style.right = '';
  document.body.style.width = '';
  window.scrollTo(0, scrollYActual);
}

function cerrarCarta() {
  if (!cartaAbierta) return;
  cartaAbierta = false;
  if (cartaPanel) { cartaPanel.hidden = true; cartaPanel.classList.remove('abierto'); }
  if (cartaOverlay) { cartaOverlay.hidden = true; cartaOverlay.classList.remove('visible'); }
  if (observerCategorias) { observerCategorias.disconnect(); observerCategorias = null; }
  desbloquearScrollFondo();
  try {
    if (history.replaceState) {
      history.replaceState(null, '', window.location.pathname + window.location.search);
    } else {
      window.location.hash = '';
    }
  } catch (e) {}
  if (ultimoFoco && typeof ultimoFoco.focus === 'function') {
    try { ultimoFoco.focus(); } catch (e) {}
  }
}

function abrirCartaUI() {
  if (!cartaPanel || !cartaOverlay) return;
  cartaPanel.hidden = false;
  cartaOverlay.hidden = false;
  requestAnimationFrame(() => {
    cartaPanel.classList.add('abierto');
    cartaOverlay.classList.add('visible');
    cartaPanel.focus({ preventScroll: true });
  });
  bloquearScrollFondo();
  cartaAbierta = true;
}

function hashParaCarta(sucursalId, cartaId) {
  if (cartaId) return `#carta-${sucursalId}-${cartaId}`;
  return `#carta-${sucursalId}`;
}

function construirLinkWhatsapp(sucursal, carta) {
  const numero = sucursal.whatsapp || (sucursal.botones && sucursal.botones.whatsapp);
  if (!numero) return '#';
  let texto = `Hola!%20Quiero%20hacer%20un%20pedido%20en%20Piedra%20Mora%20${encodeURIComponent(sucursal.nombre)}`;
  if (carta && carta.nombre && carta.nombre !== 'Carta') {
    texto += `%20(${encodeURIComponent(carta.nombre)})`;
  }
  return `https://wa.me/${numero}?text=${texto}`;
}

function renderCarta(sucursalId, carta) {
  const sucursal = SUCURSALES[sucursalId];
  if (!sucursal) return;
  if (cartaTituloSucursal) cartaTituloSucursal.textContent = sucursal.nombre;
  if (cartaTituloCarta) cartaTituloCarta.textContent = (carta.nombre && carta.nombre !== 'Carta') ? carta.nombre : '';

  if (cartaWhatsappWrap && cartaWhatsapp) {
    const mostrarWa = carta.mostrarWhatsapp !== false;
    if (mostrarWa) {
      cartaWhatsappWrap.hidden = false;
      const link = construirLinkWhatsapp(sucursal, carta);
      cartaWhatsapp.href = link;
      cartaWhatsapp.setAttribute('onclick', `trackearClicCarta('whatsapp_carta', '${sucursalId}', '${String(sucursal.nombre).replace(/'/g, "\\'")}', {carta_id: '${carta.id}'})`);
    } else {
      cartaWhatsappWrap.hidden = true;
      cartaWhatsapp.href = '#';
      cartaWhatsapp.removeAttribute('onclick');
    }
  }

  if (cartaActualizadoFecha) cartaActualizadoFecha.textContent = carta.actualizado || '';

  if (cartaChips) cartaChips.innerHTML = '';
  if (cartaCategorias) cartaCategorias.innerHTML = '';

  if (!carta.categorias || carta.categorias.length === 0) {
    if (cartaContenido) cartaContenido.hidden = false;
    if (cartaSelector) cartaSelector.hidden = true;
    return;
  }

  if (cartaContenido) cartaContenido.hidden = false;
  if (cartaSelector) cartaSelector.hidden = true;

  const scrollContenedor = document.querySelector('.carta-panel-inner');

  carta.categorias.forEach((cat, idx) => {
    const catId = `cat-${sucursalId}-${carta.id}-${idx}`.replace(/[^a-zA-Z0-9-_]/g, '_');

    if (cartaChips) {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'carta-chip';
      chip.dataset.cat = catId;
      chip.textContent = cat.nombre;
      chip.addEventListener('click', () => {
        const el = document.getElementById(catId);
        if (el && scrollContenedor) {
          const offset = 130;
          const top = el.getBoundingClientRect().top + scrollContenedor.scrollTop - offset;
          scrollContenedor.scrollTo({ top, behavior: 'smooth' });
          cartaChips.querySelectorAll('.carta-chip').forEach(c => c.classList.remove('activo'));
          chip.classList.add('activo');
        }
      });
      cartaChips.appendChild(chip);
    }

    if (!cartaCategorias) return;
    const catWrap = document.createElement('section');
    catWrap.className = 'carta-cat';
    catWrap.id = catId;

    const banner = document.createElement('div');
    banner.className = 'carta-cat-banner';
    const imgBanner = document.createElement('img');
    if (cat.foto && cat.foto !== '') {
      imgBanner.src = cat.foto;
    } else {
      imgBanner.src = 'assets/logo.png';
      imgBanner.classList.add('placeholder-logo');
    }
    imgBanner.alt = cat.nombre;
    imgBanner.loading = 'lazy';
    imgBanner.decoding = 'async';
    banner.appendChild(imgBanner);
    const bannerTitle = document.createElement('div');
    bannerTitle.className = 'carta-cat-titulo';
    bannerTitle.textContent = cat.nombre;
    banner.appendChild(bannerTitle);
    catWrap.appendChild(banner);

    const lista = document.createElement('div');
    lista.className = 'carta-productos';
    (cat.productos || []).forEach(prod => {
      const prodEl = document.createElement('article');
      prodEl.className = 'carta-producto';

      const fotoWrap = document.createElement('div');
      fotoWrap.className = 'carta-producto-foto-wrap';
      const imgProd = document.createElement('img');
      imgProd.className = 'carta-producto-foto';
      if (prod.foto && prod.foto !== '') {
        imgProd.src = prod.foto;
        imgProd.alt = prod.nombre;
      } else {
        imgProd.src = 'assets/logo.png';
        imgProd.alt = prod.nombre;
        imgProd.classList.add('placeholder-logo');
      }
      imgProd.loading = 'lazy';
      imgProd.decoding = 'async';
      imgProd.width = 120;
      imgProd.height = 120;
      fotoWrap.appendChild(imgProd);

      const info = document.createElement('div');
      info.className = 'carta-producto-info';
      const nombre = document.createElement('div');
      nombre.className = 'carta-producto-nombre';
      nombre.textContent = prod.nombre;
      const desc = document.createElement('div');
      desc.className = 'carta-producto-desc';
      desc.textContent = prod.descripcion || '';
      info.appendChild(nombre);
      info.appendChild(desc);

      const precio = document.createElement('div');
      precio.className = 'carta-producto-precio';
      precio.textContent = formatearPrecioAR(prod.precio);

      prodEl.appendChild(fotoWrap);
      prodEl.appendChild(info);
      prodEl.appendChild(precio);
      lista.appendChild(prodEl);
    });
    catWrap.appendChild(lista);
    cartaCategorias.appendChild(catWrap);
  });

  if (cartaChips) {
    const firstChip = cartaChips.querySelector('.carta-chip');
    if (firstChip) firstChip.classList.add('activo');
  }

  if (observerCategorias) { observerCategorias.disconnect(); observerCategorias = null; }
  observerCategorias = new IntersectionObserver((entradas) => {
    let mejor = null;
    let mejorRatio = -1;
    entradas.forEach(ent => {
      if (ent.isIntersecting && ent.intersectionRatio > mejorRatio) {
        mejorRatio = ent.intersectionRatio;
        mejor = ent.target;
      }
    });
    if (mejor && cartaChips) {
      const id = mejor.id;
      cartaChips.querySelectorAll('.carta-chip').forEach(c => {
        if (c.dataset.cat === id) c.classList.add('activo');
        else c.classList.remove('activo');
      });
    }
  }, {
    root: scrollContenedor || null,
    threshold: [0.25, 0.5, 0.75],
    rootMargin: '-140px 0px -40% 0px'
  });

  if (cartaCategorias) {
    cartaCategorias.querySelectorAll('.carta-cat').forEach(sec => observerCategorias.observe(sec));
  }
}

async function abrirCartaPorSucursal(sucursalId, cartaIdForzado = null) {
  const sucursal = SUCURSALES[sucursalId];
  if (!sucursal) return;
  await cargarCartasEnSegundoPlano();
  const cartas = CARTAS_POR_SUCURSAL[sucursalId] || [];
  if (!cartas || cartas.length === 0) return;

  ultimoFoco = document.activeElement;
  trackearClicCarta('ver_carta', sucursalId, sucursal.nombre, {});

  if (cartas.length === 1) {
    if (cartaSelector) cartaSelector.hidden = true;
    if (cartaContenido) cartaContenido.hidden = true;
    abrirCartaUI();
    renderCarta(sucursalId, cartas[0]);
    try { history.pushState(null, '', hashParaCarta(sucursalId, cartas[0].id)); } catch (e) {}
    return;
  }

  if (cartaContenido) cartaContenido.hidden = true;
  if (cartaSelector) cartaSelector.hidden = false;
  if (cartaSelectorOpciones) cartaSelectorOpciones.innerHTML = '';
  cartas.forEach(carta => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'carta-selector-btn';
    btn.textContent = carta.nombre || 'Carta';
    btn.addEventListener('click', () => {
      if (cartaSelector) cartaSelector.hidden = true;
      abrirCartaUI();
      renderCarta(sucursalId, carta);
      try { history.pushState(null, '', hashParaCarta(sucursalId, carta.id)); } catch (e) {}
    });
    if (cartaSelectorOpciones) cartaSelectorOpciones.appendChild(btn);
  });

  if (cartaTituloSucursal) cartaTituloSucursal.textContent = sucursal.nombre;
  if (cartaTituloCarta) cartaTituloCarta.textContent = '';
  if (cartaWhatsappWrap) cartaWhatsappWrap.hidden = true;

  abrirCartaUI();
  try { history.pushState(null, '', hashParaCarta(sucursalId, cartaIdForzado)); } catch (e) {}
}

function abrirDesdeHash() {
  const hash = window.location.hash;
  if (!hash) return;
  // Buscar patrón: #carta-sucursal-id o #carta-sucursal-id-carta-id
  // Capturar todo después de #carta- como resto
  const rest = hash.replace(/^#carta-/, '');
  if (!rest) return;
  // Intentar encontrar sucursal
  const sucIds = Object.keys(SUCURSALES || {});
  // Buscar sucursal cuyo id esté al inicio
  let sucursalId = null;
  let cartaId = null;
  for (let i = 0; i < sucIds.length; i++) {
    const sid = sucIds[i];
    if (rest === sid) {
      sucursalId = sid;
      break;
    }
    if (rest.startsWith(sid + '-')) {
      sucursalId = sid;
      cartaId = rest.substring(sid.length + 1);
      break;
    }
  }
  if (!sucursalId || !SUCURSALES[sucursalId]) {
    // fallback regex más permisivo
    const m = hash.match(/^#carta-([a-z0-9-]+)(?:-(.+))?$/i);
    if (m) {
      sucursalId = m[1];
      cartaId = m[2] || null;
    } else {
      return;
    }
  }
  if (!SUCURSALES[sucursalId]) return;
  cargarCartasEnSegundoPlano().then(() => {
    abrirCartaPorSucursal(sucursalId, cartaId);
  });
}

document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-accion="ver-carta"]');
  if (btn) {
    const sid = btn.getAttribute('data-sucursal-id');
    if (sid) abrirCartaPorSucursal(sid);
  }
});

if (cartaCerrar) cartaCerrar.addEventListener('click', cerrarCarta);
if (cartaOverlay) cartaOverlay.addEventListener('click', cerrarCarta);

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    cerrarCarta();
    return;
  }
  if (e.key === 'Tab' && cartaAbierta && cartaPanel) {
    const focusables = cartaPanel.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
    const list = Array.from(focusables).filter(el => {
      return !el.hasAttribute('disabled') && el.offsetWidth > 0 && el.offsetHeight > 0 && el.getAttribute('hidden') === null;
    });
    if (list.length === 0) return;
    const first = list[0];
    const last = list[list.length - 1];
    if (e.shiftKey) {
      if (document.activeElement === first) {
        last.focus();
        e.preventDefault();
      }
    } else {
      if (document.activeElement === last) {
        first.focus();
        e.preventDefault();
      }
    }
  }
});

window.addEventListener('hashchange', () => {
  if (!window.location.hash) {
    cerrarCarta();
    return;
  }
  abrirDesdeHash();
});

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', precargarCartas);
} else {
  precargarCartas();
}

/* ===== Inicio ===== */
cargarSucursales();