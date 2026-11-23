document.querySelectorAll('form input').forEach((input) => input.setAttribute('autocomplete', 'off'));

const dialog = document.querySelector('#car-dialog');
const name = document.querySelector('#dialog-name');
const spec = document.querySelector('#dialog-spec');
const status = document.querySelector('#dialog-status');
const showCar = (button) => {
  if (!dialog) return;
  name.textContent = button.dataset.name;
  spec.textContent = button.dataset.spec;
  status.textContent = `Current status: ${button.dataset.status}`;
  dialog.showModal();
};
document.querySelectorAll('.inspect').forEach((button) => button.addEventListener('click', (event) => { event.stopPropagation(); showCar(button); }));
document.querySelectorAll('.car-card').forEach((card) => card.addEventListener('click', () => showCar(card.querySelector('.inspect'))));
document.querySelector('.dialog-close')?.addEventListener('click', () => dialog.close());
document.querySelector('.filter-button')?.addEventListener('click', (event) => {
  const onlyReady = event.currentTarget.dataset.filter === 'all';
  document.querySelectorAll('.car-card').forEach((card) => card.classList.toggle('is-hidden', onlyReady && card.dataset.status !== 'Track ready'));
  event.currentTarget.dataset.filter = onlyReady ? 'ready' : 'all';
  event.currentTarget.textContent = onlyReady ? 'Show all' : 'Track-ready only';
});
