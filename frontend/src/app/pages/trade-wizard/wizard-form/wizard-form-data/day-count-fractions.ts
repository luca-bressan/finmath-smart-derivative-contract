export interface DayCountFraction{
  id: string,
  fullName: string,
}

export const dayCountFractions: DayCountFraction[] = [
  {
    id: 'ACT/ACT',
    fullName: 'ACT/ACT',
  },
  {
    id: 'ACT/360',
    fullName: 'ACT/360',
  },
  {
    id: '30E/360',
    fullName: '30E/360',
  }
];
