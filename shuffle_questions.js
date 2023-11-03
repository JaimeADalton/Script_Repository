// mezcla aleatoriamente utilizando el algoritmo de Fisher-Yates. Luego, selecciona todas las preguntas en una página web por su clase 'toggle', las mezcla y las vuelve a agregar al contenedor de preguntas en un orden aleatorio.

// https://www.freecram.com/Huawei-certification/H13-624-ENU-exam-questions.html


// Función para mezclar aleatoriamente un array
function shuffle(array) {
  let currentIndex = array.length, randomIndex;

  // Mientras queden elementos a mezclar...
  while (currentIndex != 0) {

    // Seleccionar un elemento restante...
    randomIndex = Math.floor(Math.random() * currentIndex);
    currentIndex--;

    // E intercambiarlo con el elemento actual
    [array[currentIndex], array[randomIndex]] = [
      array[randomIndex], array[currentIndex]];
  }

  return array;
}

// Seleccionar todas las preguntas por su clase 'toggle'
const questions = document.querySelectorAll('.toggle');
const questionsArray = Array.from(questions);

// Mezclar las preguntas
const shuffledQuestions = shuffle(questionsArray);

// Obtener el elemento contenedor de las preguntas
const container = questions[0].parentNode;

// Limpiar el contenedor
while (container.firstChild) {
  container.removeChild(container.firstChild);
}

// Añadir las preguntas mezcladas de nuevo al contenedor
shuffledQuestions.forEach(question => {
  container.appendChild(question);
});
